#!/usr/bin/perl
package CueParse;
use strict;
use Carp;
#use Audio::FLAC::Header;
use File::Basename;

BEGIN {
    use Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(parse);
}

sub parse($) {
    my $cuefile = shift;
    open (CUE, "<", $cuefile) or die "$cuefile: $!";
    my @cuelines = <CUE>;

    for (my $i = 0; $i<@cuelines; $i++){
       if ( $cuelines[$i] !~ m/^\s*(?:CATALOG|CDTEXTFILE|FILE|FLAGS|INDEX|ISRC|PERFORMER|POSTGAP|PREGAP|REM|SONGWRITER|TITLE|TRACK)/o ) {
           die "неизвестный идентификатор в cue: ".($i+1)." строка\n";
       }
    }

    my $singleFile = 1 if ( grep m/^\s*FILE/o, @cuelines ) == 1;
    my $i = 0;
    my $line;
    my ( $genre, $date, $album, $album_artist, $disc_number, $total_discs );
    while ( $line = $cuelines[$i++] and $line !~ m/^\s*TRACK/o ) {
        $genre = $1 if $line =~ m/^\s*REM\s+GENRE\s+"?(.*?)"?\s*$/o;
        $date = $1 if $line =~ m/^\s*REM\s+DATE\s+"?(\d{4}(?:-\d{4})?)"?\s*$/o;
        #типа переиздания обозначаю, как 1975-2004
        $album_artist = $1 if $line =~ m/^\s*PERFORMER\s+"(.*)"\s*$/o;
        $disc_number = $1 if $line =~ m/^\s*REM\s+DISCNUMBER\s+"?(\d{1,2})"?\s*$/o;
        $total_discs = $1 if $line =~ m/^\s*REM\s+TOTALDISCS\s+"?(\d{1,2})"?\s*$/o;
        $album = $1 if $line =~ m/^\s*TITLE\s+"(.*)"\s*$/o;
        #print $line."\n".$album_artist."\n";
        $singleFile = $1 if $singleFile && $line =~ m/^\s*FILE\s+"(.*)"\s*WAVE$/o;
    }

    s/''/"/go for ($album, $album_artist, $date, $genre, $singleFile);
    my %meta = ( album => $album, artist => $album_artist,
        date => $date, tracks => [] );
    $meta{genre} = $genre;
    $meta{discnumber} = $disc_number+0 if $disc_number;
    $meta{totaldiscs} = $total_discs+0 if $total_discs;
    $meta{singleFile} = $singleFile if $singleFile;

    my $prev_track = 0;
    my $fileCount = 0;
    my $rest = 0;
    foreach (0..$#cuelines) {
        $line = $cuelines[$_];
        my ( $track ) = ( $line =~ m/^\s*TRACK\s+(\d{2,})\s+AUDIO/o );
        if ($track) {
            $track+=0;#избавился от ведущих нулей
            die "кажется пропущен трек!\n" if $track != $prev_track+1;

            $i = $_;
            my ( $title, $performer, $file, $index1 );
            my $index0 = undef;
            my $filelength = 0;
            ( $file ) = $cuelines[$_-1] =~ m/^\s*FILE\s+"(.+)"/o;

            my $next_line;
            while ( ( $next_line = $cuelines[++$i] ) && 
                $next_line !~ m/^\s*TRACK/o) {

                $title = $1 if $next_line =~ m/^\s*TITLE\s+"(.*)"/o;
                $performer = $1 if $next_line =~ m/^\s*PERFORMER\s+"(.*)"/o;
                ( $file ) = $next_line =~ m/^\s*FILE\s+"(.*)"/o
                    if (not $file);
                # обработка pregap hidden track
                if ( $track == 1 and
                     $next_line =~ m/^\s*INDEX\s+00\s+00:00:00/o and
                     ( my $tempfile) = $cuelines[$i+1] =~ m/^\s*FILE\s+"(.*)"/o
                    ) 
                {
                    s/''/"/go for ($file, $performer);
                    my $trackMeta = {
                        performer => $performer,
                        title => 'Pregap',
                        track_no => 0
                    };
                    $trackMeta->{'file'} = $file unless $singleFile;
                    push @{ $meta{'tracks'} },$trackMeta;

                    $file = $tempfile;
                };
            }

            s/''/"/go for ($file, $performer, $title, $track);
            my $trackMeta = {performer => $performer, title => $title, track_no => $track };
            $trackMeta->{'file'} = $file unless $singleFile;
            push @{ $meta{'tracks'} },$trackMeta;
            $prev_track = $track;
        }
    }
    close CUE;
    return \%meta;
}

1;
