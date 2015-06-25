#!/usr/bin/env perl
use FindBin;

use strict;
use warnings;
use Data::Dumper;
use Fuse;
use File::Basename;
use File::Glob ':glob';
use Getopt::Long;

use lib "$FindBin::RealBin/lib";
use CueParse;
use Flac::TieFilehandle;

my $musiclib = $ENV{'HOME'}.'/MUSIC/lossless/';
my $mountpoint = $ENV{'HOME'}."/FUSE_MUSIC/";
my $debug = 0;
GetOptions ("musiclib=s" => \$musiclib, "mountpoint=s" => \$mountpoint, "debug" => \$debug);

# here is where you got new metainfo
sub getMeta {
    my $flac_file = shift;
    my @cueFiles = glob(dirname($flac_file).'/*.cue');
    my $taghash;
    if ($cueFiles[0]) {
        my $cueHash = parse($cueFiles[0]);

        my $track_meta;
        foreach my $track (@{$cueHash->{'tracks'}}) {
            $track_meta = $track if $track->{'file'} eq basename($flac_file);
        }

        $taghash = {
            'ALBUM' => $cueHash->{'album'},
            'DATE' => $cueHash->{'date'},
            'GENRE' => $cueHash->{'genre'},
        };
        $taghash->{'ALBUMARTIST'} = $cueHash->{'artist'} if $cueHash->{'artist'};

        if ($track_meta) {
            $taghash->{'TITLE'} = $track_meta->{'title'};
            $taghash->{'ARTIST'} = $track_meta->{'performer'} || $cueHash->{'artist'};
            $taghash->{'ALBUM'} = $cueHash->{'album'};
            $taghash->{'TRACKNUMBER'} = $track_meta->{'track_no'};
        }
        else {
            warn "Track $flac_file not found in cue-file: ".$cueFiles[0]."\n";
        }
    }
    else {
        warn "Cue-file for $flac_file not found\n";
    }

    return $taghash;
}

sub findOrig {
    my $path = shift;
    my $dirname = dirname($musiclib.$path);
    my $basename = basename($musiclib.$path);
    if (-e $musiclib.$path) {
        return $musiclib.$path
    }
    else {
        my $fileMask = $basename;
        $fileMask =~ s/([\{\}\[\]\*\?\~\\])/\\$1/g;
        $fileMask =~ s/_/?/g;
        my @matchFiles = glob($dirname.'/'.$fileMask);
        if (@matchFiles == 1) {
            return $matchFiles[0];
        }
        else {
            warn "original file for $path not found\n";
        }
    }
}

sub getdir {
    my $dirname = shift;

    my @subdirs;
    opendir(my $dh, $musiclib.$dirname) || die "can't opendir $musiclib$dirname: $!";
    while(readdir $dh) {
        my $file_with_path = $musiclib.$dirname.'/'.$_;
        # замена символов, недоступных в Windows на символ _
        # TODO: пока только для файлов, нужно еще для директорий.
        if (-f $file_with_path) {
            push(@subdirs,$_) if $_ eq 'cover.jpg';
            s/[:?"]/_/g;
            push(@subdirs,$_) if $file_with_path =~ m/.*\.flac$/;
        }
        elsif (-d $file_with_path) {
            next if $_ eq 'covers';
            push(@subdirs,$_);
        }
    }
    return (@subdirs, 0);
}

sub getattr {
    my $origPath = findOrig(shift);
    my @stat = stat($origPath);
    my $flacfile = ($origPath =~ m/.*\.flac$/)?$origPath:'';
    if ($flacfile) {
        my $flh;
        { no warnings;
        $flh = *FLFL; }
        my %info;
        tie *$flh, "TieFilehandle", $flacfile, getMeta($flacfile), \%info;
        $stat[7] = $stat[7] - $info{'old_vorbis_length'} + $info{'new_vorbis_length'};
        close $flh;
    }
    return @stat;
}

# TODO: директории доступные только для чтения
sub open {
    my $file = findOrig(shift);

    return -ENOENT() unless $file;
    return -EISDIR() if -d $file;

    my $flacfile = ($file =~ m/.*\.flac$/)?$file:'';

    my $fh;
    if ($flacfile and (my $new_taghash = getMeta($flacfile))) {
        { no warnings;
        $fh = *FLACFILE; }
        tie *$fh, "TieFilehandle", $flacfile, $new_taghash;
    }
    else {
        open $fh, "<", $file;
        binmode $fh;
    }
    return 0, $fh;
}

sub read {
    my $path = findOrig(shift);
    my ( $bytes, $offset, $fh ) = @_;
    my $buffer;
    # учесть offset
    my $status = read( $fh, $buffer, $bytes);#, $offset );
    if ($status > 0) {
        return $buffer;
    }
    return $status;
}

sub release {
    my $path = findOrig(shift);
    my ( $flags, $fh) = @_;
    close($fh);
}

Fuse::main(
    debug       => $debug,
    mountpoint  => $mountpoint,
    mountopts   => 'allow_other',
    getdir      => \&getdir,
    getattr     => \&getattr,
    threaded    => 0,
    open        => \&open,
    read        => \&read,
    release     => \&release
);
