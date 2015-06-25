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
my $debug = 0;
my $output;
GetOptions ("library=s" => \$library,
            "db=s"  => \$dbPath,
            "output=s"  => \$output,
            "debug" => \$debug);
die "не переданы пути к cue-фалам\n" unless @ARGV;

open ( DB, "<", $dbPath ) or 
    die "невозможно открыть файл $dbPath на чтение $!\n";
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

        #$newMeta{'Album'} =~ s/\s*\((?:cd|disc)\s+(\d+)\)//i;
        #$newMeta{'Disc'} = $1 if $1;
        $newMeta{'Disc'} = $meta->{discnumber} if $meta->{discnumber};

        my @paste;
        foreach (qw/Artist Title Album Date/) {
            die "$cueFile: не полный cueFile (не все метаданные заполнены)\n"
                unless $newMeta{$_};
            push @paste, $_.': '.$newMeta{$_};
        }
        die "$cueFile: номер трека не является неотрицательным целым числом\n"
            unless $newMeta{'Track'} =~ m/^\d+$/;
        push @paste, 'Track'.': '. sprintf('%02d',$newMeta{'Track'});

        if ($meta->{'artist'}) {
            push @paste, 'AlbumArtist: '.$meta->{'artist'};
        }
        push @paste, 'Disc: '.$newMeta{'Disc'} if $newMeta{'Disc'};
        push @paste, 'Genre: '.$newMeta{'Genre'} if $newMeta{'Genre'};

        my $flacFile = File::Spec->catfile($filesdir,$file);
        die "файл $flacFile не доступен\n" 
            unless -f $flacFile and -r $flacFile;
        my $dbFileDir = File::Spec->abs2rel($filesdir,$library);

        my $flag = 0;
        SEARCHDIR: for (my $i=0;$i<scalar(@db);$i++) {
            if ($db[$i] eq "begin: $dbFileDir") {
                SEARCHFILE: for (my $k=$i;$k<scalar(@db);$k++) {
                    last SEARCHFILE if $db[$k] eq "end: $dbFileDir";
                    if ($db[$k] eq "song_begin: $file") {
                        print STDERR "found $dbFileDir/$file\n" if $debug;
                        $flag = 1;
                        my ($beg,$end);
                        META: for (my $j=$k;$j<scalar(@db);$j++) {
                            $beg = $j+1 if $db[$j] =~ m/^Time:/;
                            $end = $j-1 if $db[$j] =~ m/^mtime:/;
                            last META if $db[$j] =~ m/^(song_end)/;
                        }
                        print "$beg-$end\n" if $debug;
                        splice (@db,$beg,$end-$beg+1,@paste);
                        last SEARCHFILE;
                    }
                }
            }
        }
        print STDERR "файл $dbFileDir/$file не найден в базе\n" unless $flag;
    }
}

open (DB, ">", $output || $dbPath) or die "запись невозможна: $!\n";
print DB join "\n",@db;
close DB;
