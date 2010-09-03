#!/usr/bin/perl

# tumblrrss.pl - Tumblr "dashboard" RSS feed generator.

# (c) 2009 L. Diener, licensed under the WTFPL, see below.

#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                     Version 2, December 2004           
#                                                        
#  Copyright (C) 2004 Sam Hocevar                        
#   14 rue de Plaisance, 75014 Paris, France             
#  Everyone is permitted to copy and distribute verbatim or modified
#  copies of this license document, and changing it is allowed as long
#  as the name is changed.                                            
#                                                                     
#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE             
#    TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION  
#                                                                     
#   0. You just DO WHAT THE FUCK YOU WANT TO.                         

use strict;
use warnings;

use lib ".";
use WWW::Tumblr;
use POSIX;

# Config
my $TUMBLR_MAIL = 'email';
my $PASSWORD = 'password';

sub simple_html_scrub( $ ) {
	my ( $html ) = @_;
	$html =~ s/(<[^>]*>)//gis;
	$html =~ s/(&lt;.*?&gt;)//gis;
	return $html;
}

my $t = WWW::Tumblr->new;
$t->email( $TUMBLR_MAIL );
$t->password( $PASSWORD );

my $xml = $t->dashboard(
	'start' => '0',
	'num' => '20',
	'auth' => '1',
) or die( "Tumblr dashboard read failed." );

# Output header
print <<RSS
Content-type: application/xhtml+xml

<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
  <channel>
    <title>Tumblr</title>
    <icon>http://assets.tumblr.com/images/favicon.gif?2</icon>
    <link>http://www.tumblr.com/dashboard</link>
    <description>Tumblr dashboard</description>
    <language>ja</language>
    <ttl>30</ttl>
RSS
;

# Parse and output.
while( $xml =~ /<post(.*?)<\/post>/sgi ) {
	my $post = $1;
	
	my ( $post_params ) = $post =~ /([^>]*)/;

	if( !$post_params ) {
		next;
	}
	
	my ( $type ) = $post_params =~ /type="([^"]*)"/;
	my ( $user ) = $post_params =~ /tumblelog="([^"]*)"/;
	my ( $date ) = $post_params =~ /unix-timestamp="([^"]*)"/;
	my ( $url ) = $post_params =~ /url="([^"]*)"/;
	my ( $reblog ) = $post_params =~ /reblogged-from-name="([^"]*)"/;
	if( !$url || !$date ) {
		next;
	}
	my $rssdate = strftime('%a, %d %b %Y %T %Z', gmtime($date) );

	my $title = "$user" . ($reblog ? " reblogging $reblog" : "" );
	my $desc = "";
	
	if( $type eq 'regular' ) {
		my ( $regtitle ) = $post =~ /<regular-title>(.*?)<\/regular-title>/s;
		chomp( $regtitle );
		$title .= ": $regtitle";
		( $desc ) = $post =~ /<regular-body>(.*?)<\/regular-body>/s;
		chomp $desc;
	}

	if( $type eq 'quote' ) {
		my ( $quotetext ) = $post =~ /<quote-text>(.*?)<\/quote-text>/s;
		chomp( $quotetext );
		my $quotetmp = simple_html_scrub( $quotetext );
		my ( $quotesub ) = $quotetmp =~ /([^\.]*)\./;
		if( !$quotesub ) {
			$quotesub = $quotetmp;
		}
		$title .= ": $quotesub. [...]";
		my ( $quotesource ) = $post =~ /<quote-source>(.*?)<\/quote-source>/s;
		chomp $quotesource;
		$quotesource =~ s/&lt;p&gt;//gi;
		$quotesource =~ s/&lt;\/p&gt;/ /gi;
		$desc = "$quotetext ($quotesource)";
	}

	if( $type eq 'photo' ) {
		my ( $phototext ) = $post =~ /<photo-caption>(.*?)<\/photo-caption>/s;
		if( $phototext ) {
			my $phototmp = simple_html_scrub( $phototext );
			chomp( $phototext );
			my ( $photosub ) = $phototmp =~ /([^\.]*)\./;
			if( !$photosub ) {
				$photosub = $phototmp;
			}
			$title .= ": $photosub. [...]";
			$desc = "&lt;p&gt;$phototext&lt;/p&gt;";
		}
		else {
			$title = ": (Pictures only)";
		}

		my %urls_used = ();
		my $cur_link;
		while( $post =~ /<(photo-(?:link-)?url)(.*?)<\/photo-(?:link-)?url>/sgi ) {
			if( lc( $1 ) eq "photo-url" ) {
				my ( $photourl ) = $2 =~ />(.*)/s;
				chomp $photourl;
				my ( $server, $base_url ) = $photourl =~ /^http:\/\/(.*)\/tumblr_([^_]*)/;
				$base_url =~ s/(.*)o1/$1/;
				if( !$urls_used{$base_url} ) {
					$urls_used{$base_url} = 1;
					if( $cur_link ) {
						$desc .= "&lt;p&gt;&lt;a href=\"$cur_link\"&gt;&lt;img src=\"$photourl\" /&gt;&lt;/a&gt;&lt;/p&gt;";
					}
					else {
						$desc .= "&lt;p&gt;&lt;img src=\"$photourl\" /&gt;&lt;/p&gt;";
					}
				}
			}
			else {
				( $cur_link ) = $2 =~ />(.*)/s;
				chomp $cur_link;
			}
		}
	}

	if( $type eq 'link' ) {
		my ( $linktext ) = $post =~ /<link-text>(.*?)<\/link-text>/s;
		chomp( $linktext );
		if( !$linktext ) {
			$linktext = "(Link)";
			$title .= ": (Link)";
		}
		else {
			my $linktmp = simple_html_scrub( $linktext );
			my ( $linksub ) = $linktmp =~ /([^\.]*)\./;
			if( !$linksub ) {
				$linksub = $linktmp;
			}
			$title .= ": $linksub. [...]";
		}
		my ( $linkurl ) = $post =~ /<link-url>(.*?)<\/link-url>/s;
		chomp $linkurl;
		my ( $linkdesc ) = $post =~ /<link-description>(.*?)<\/link-description>/s;
		chomp $linkdesc;
		if( !$linkdesc ) {
			if( !$linktext eq "(Link)" ) {
				$linkdesc = $linktext;
			}
			else {
				$linkdesc = "";
			}
		}
		$linkurl =~ s/&lt;p&gt;//gi;
		$linkurl =~ s/&lt;\/p&gt;/ /gi;
		$desc = "&lt;a href=\"$linkurl\"&gt;$linktext&lt;/a&gt;$linkdesc";
	}


	if( $type eq 'conversation' ) {
		my ( $convtitle ) = $post =~ /<line(.*?)<\/line>/s;
		chomp( $convtitle );
		$convtitle =~ s/>(.*)/$1/s;
		my ( $convsub ) = $convtitle =~ /([^\.]*)\./;
		if( !$convsub ) {
			$convsub = $convtitle;
		}
		$title .= ": $convsub. [...]";
		$desc .= "&lt;p&gt;";
		while( $post =~ /<line .*? label=\"([^"]*)\">([^<]*)</sgi ) {
			$desc .= "&lt;b&gt;$1&lt;/b&gt; $2&lt;br/&gt;";
		}
		$desc .= "&lt;/p&gt;";
	}
	
	# Build RSS item.
	print "<item>\n";
	print "<title>$title</title>\n";
	print "<description>$desc</description>\n";
	print "<guid>$url</guid>\n";
	print "<link>$url</link>\n";
	print "<pubDate>$rssdate</pubDate>\n";
	print "</item>\n";
}

# Output footer
print "</channel>\n</rss>\n";
