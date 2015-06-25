#!/usr/bin/perl
use FindBin;
use lib "$FindBin::RealBin/lib";

use Data::Dumper;

use strict;
use File::Basename;
use File::Copy;
use Audio::FLAC::Header;
use CueParse;

while (my $cueFile = shift) {
    my $cue = parse($cueFile) or die "неверный $cueFile";
    #print Dumper $cue;
    #exit;
    my $dir = dirname($cueFile);

    opendir cueDir, $dir;
    my $flacCount = grep /\.flac$/, readdir(cueDir);
    #print join "\n", @files;
    close cueDir;

    die "не совпадает количество flac-файлов и треков в $cueFile!"
        if @{ $cue->{'tracks'} } != $flacCount;
    die "не задан альбом в cue в $cueFile"
        if ! $cue->{'album'};

    #print Dumper $cue;
    foreach (@{ $cue->{'tracks'} }) {
        my $fileFromCue = $_->{'file'}; 
        #print Dumper $_;
        $fileFromCue =~ s/''/"/g;
        $fileFromCue = "$dir/".$fileFromCue;

        unless ( -f $fileFromCue && -w $fileFromCue && -r $fileFromCue ) {
            print STDERR "$fileFromCue не доступен\n";
            next;
        }

        my $flac = Audio::FLAC::Header->new($fileFromCue);
        my $tags = $flac->tags();

        #for (keys %$tags) {
        #    print "$_: $tags->{$_}\n";
        #}

        #print Dumper $tags;

        #for (keys %$tags) {
        #    $tags->{$_} = undef;
        #}

        %$tags = ();
        $tags->{'ALBUM ARTIST'} = $cue->{'artist'} if $cue->{'artist'};
        $tags->{'DATE'} = $cue->{'date'};
        $tags->{'ALBUM'} = $cue->{'album'};
        $tags->{'GENRE'} = $cue->{'genre'};
        $tags->{'ARTIST'} = $_->{'performer'} || $cue->{'artist'};
        $tags->{'TITLE'} = $_->{'title'};
        $tags->{'TRACKNUMBER'} = $_->{'track_no'};

        #print Dumper $tags;
        $flac->write();
        #for (keys %$tags) {
        #    printf "$_: %s\n",$flac->tags()->{$_};
        #}

        my $newFile = $fileFromCue;
        if ( $newFile =~ s/[:?"]/_/g ) {
            rename $fileFromCue,$newFile;
        }
    }
}
