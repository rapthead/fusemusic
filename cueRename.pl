#!/usr/bin/perl
use FindBin;
use lib "$FindBin::RealBin/lib";

use Data::Dumper;

use strict;
use File::Basename;
use CueParse;

my $cueFile = shift;
#print $cueFile."\n";
my $cue = parse($cueFile) or die "неверный $cueFile";
#print Dumper $cue;
my $dir = dirname($cueFile);

opendir cueDir, $dir;
my @files = grep /\.(?:flac|cue|log|cue\.orig)$/i, readdir(cueDir);
my @flacFiles = sort grep /\.flac$/i, @files;
my $logFile = (grep /\.log$/i, @files)[0];
my $cueOrigFile = (grep /\.cue\.orig$/i, @files)[0];
#print join "\n", @files;

/^\d{2}\D/ or die "не хороший формат названия flac-файлов" for @flacFiles;

#print scalar(@{ $cue->{'tracks'} }),'-',scalar(@flacFiles);
die "не совпадает количество flac-файлов и треков!\n"
    if @{ $cue->{'tracks'} } != @flacFiles;
die "не задан альбом в cue\n"
    if ! $cue->{'album'};
warn "не найден log-файл\n"
    if ! $logFile;

#TODO:сделать невозможность замены в rename
open CUE,"<",$cueFile or die "$!";
my @cueLines = <CUE>;
close CUE;
#убираю перевод строки unix и dos
s/[\x0D\x0A]{1,2}$// for (@cueLines);

my $i=0;
foreach (@{ $cue->{'tracks'} }) {
    #print Dumper $_;
    my $oldfile = $flacFiles[$i++] or die "не хватает flac-файлов";
    my $newfile = sprintf "%02d-%s.flac", $_->{'track_no'}, $_->{'title'};
    print $oldfile .'=>'. $newfile ."\n";
    $newfile =~ s/\//_/g;
    rename("$dir/$oldfile", "$dir/$newfile" ) or die "$!";
    my $fileFromCue = $_->{'file'};
    $fileFromCue =~ s/"/''/g;
    #print $fileFromCue . '-' . $newfile . "\n";
    # TODO: не работает с повторяющимися значениями FILE
    for (@cueLines) {
        if ( m/^(\s*FILE\s+)"(.*)"(.*)/ and $2 eq $fileFromCue ) {
            $_ = $1.'"'.$newfile.'" WAVE';
            last;
        }
    }
}

open CUE,">",$cueFile or die "$cueFile: $!";
print CUE $_."\n" for (@cueLines);
close CUE;
#print join "\n", @cueLines or die "$!";

(my $fixAlbum = $cue->{'album'}) =~ s/\//_/;
my $newLog = sprintf "%s/%s.log", $dir, $fixAlbum;
my $newCue = sprintf "%s/%s.cue", $dir, $fixAlbum;
if ($logFile) {
    rename ("$dir/$logFile", $newLog) or die "$!";
}
rename ("$cueFile", $newCue) or die "$!";
rename ("$dir/$cueOrigFile", $newCue . '.orig') or die "$!" if $cueOrigFile;
