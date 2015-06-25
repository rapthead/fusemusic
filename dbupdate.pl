#!/usr/bin/perl
use File::Spec;
use File::Basename;
use Getopt::Long;
use FindBin;
use lib "$FindBin::RealBin/lib";

use Data::Dumper;
use CueParse;
use strict;

my $library = '/home/noname/MUSIC/lossless/';
my $dbPath = '/var/lib/mpd/mpd.db';
GetOptions ("library=s" => \$library,
            "db=s"  => \$dbPath);
die "не переданы пути к cue-фалам" unless @ARGV;

open ( DB, "<", $dbPath ) or die "$!";
chomp(my @db = <DB>);
close DB;

foreach my $cueFile (@ARGV) {
    my $filesdir = dirname($cueFile);

    my $meta = parse($cueFile);
    foreach (@{ $meta->{'tracks'} }) {
        #print Dumper $_;
        my (%newMeta,$file);
        ($file,$newMeta{'Album'},$newMeta{'Artist'},
            $newMeta{'Date'},$newMeta{'Genre'},$newMeta{'Title'},
            $newMeta{'Track'}) =
            ( $_->{'file'}, $meta->{'album'}, $_->{'performer'} || $meta->{'artist'},
                $meta->{'date'}, $meta->{'genre'} || '',
                $_->{'title'}, $_->{'track_no'} );

        $newMeta{'Album'} =~ s/\s*\((?:cd|disc)\s+(\d+)\)//i;
        $newMeta{'Disc'} = $1 if $1;

        my @paste;
        foreach (qw/Artist Title Album Date Track/) {
            die "$cueFile: не полный cueFile" unless $newMeta{$_};
            push @paste, $_.': '.$newMeta{$_};
        }
        if ($meta->{'artist'} and
                ($meta->{'artist'} ne $newMeta{'Artist'})) {
            push @paste, 'AlbumArtist: '.$meta->{'artist'};
        }
        push @paste, 'Disc: '.$newMeta{'Disc'} if $newMeta{'Disc'};
        push @paste, 'Genre: '.$newMeta{'Genre'} if $newMeta{'Genre'};

        my $flacFile = File::Spec->catfile($filesdir,$file);
        die "файл $flacFile не доступен\n" 
            unless -f $flacFile and -r $flacFile;
        my $dbFile = File::Spec->abs2rel($flacFile,$library);

        my $flag = 0;
        SEARCH: for (my $i=0;$i<scalar(@db);$i++) {
            if ($db[$i] eq "file: $dbFile") {
                $flag = 1;
                my ($beg,$end);
                META: for (my $j=$i;$j<scalar(@db);$j++) {
                    $beg = $j+1 if $db[$j] =~ m/^Time:/;
                    $end = $j-1 if $db[$j] =~ m/^mtime:/;
                    last META if $db[$j] =~ m/^(key:|songList end)/;
                }
                #print "$beg-$end\n";
                splice (@db,$beg,$end-$beg+1,@paste);
                last SEARCH;
            }
        }
        print STDERR "файл $dbFile не найден в базе\n" unless $flag;
    }
}

open DB, ">", $dbPath or die "запись невозможна: $!";
print DB join "\n",@db;
close DB;
