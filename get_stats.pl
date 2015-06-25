#!/usr/bin/perl -w
use LWP::Simple;
use utf8;
use open qw(:std :utf8);
my $directory = shift;

my $nextURL = 'http://www.lastfm.ru/user/griban/tracks?page=';
for (my $i=1;$i<=198;$i++) {
    $content = get($nextURL.$i);
    print STDERR $i,"\n";
    print $1,';',$2,';',$3,"\n" while $content =~ 
        m#<td class="subjectCell">.*?<a href="/music/.+?">(.+?)</a>.*?<a href="/music/.+?">(.+?)</a>.*?<td class="dateCell last" >\s*?<abbr title="(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)">#sg;
}
