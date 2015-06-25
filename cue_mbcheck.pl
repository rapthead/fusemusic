#!/usr/bin/perl
use FindBin;
use lib "$FindBin::RealBin/lib";

use Data::Dumper;

use strict;
use utf8;
use open qw(:std :utf8);
use File::Basename;
use File::Copy;
use Audio::FLAC::Header;
use CueParse;

#sub release_info_parse {
#    my $release_info_file = shift;
#    my %info;
#    die "$release_info_file не доступен\n"
#        unless ( -f $release_info_file && -r $release_info_file );
#    open (RELEASE, "<", $release_info_file) or die "$release_info_file: $!";
#    while (my $line = <RELEASE>) {
#        $info{$1} = $2 if $line =~ m/^\s*(source|label|type|date|catalog#)\s*:\s*(.*?)\s*$/o
#    }
#    return \%info;
#    #m/^\s*REM\s+GENRE\s+"?(.*?)"?\s*$/o
#}
use Getopt::Long;

my ($pregap,$debug) = (0,0);
GetOptions ("pregap=s" => \$pregap, "debug" => \$debug);
if ($pregap) {
    $pregap =~ m/(?:(?:(\d+):)?(\d+):)?(\d+)/ or die "не действительный pregap";
    $pregap = ($1*60+$2)*75+$3;
}

my $cueFile = shift or die "ожидается аргумент";

my $cue = parse($cueFile) or die "неверный $cueFile";
my $dir = dirname($cueFile);
#print Dumper release_info_parse($dir.'/release.info');
#exit;

opendir cueDir, $dir;
my $flacCount = grep /\.flac$/, readdir(cueDir);
close cueDir;

die "не совпадает количество flac-файлов и треков!\n"
    if @{ $cue->{'tracks'} } != $flacCount;
die "не задан альбом в cue\n"
    if ! $cue->{'album'};

#print Dumper $cue;
my @offsets = ( 150 );
foreach (@{ $cue->{'tracks'} }) {
    next if $_->{track_no} == 0;
    my $fileFromCue = $_->{'file'}; 
    $fileFromCue =~ s/''/"/g;
    $fileFromCue = "$dir/".$fileFromCue;

    die "$fileFromCue не доступен\n"
        unless ( -f $fileFromCue && -r $fileFromCue );

    my $flac = Audio::FLAC::Header->new($fileFromCue);

    my $info = $flac->info();
    push @offsets,$offsets[-1]+$info->{'TOTALSAMPLES'}/588;
}
@offsets = map {$_+$pregap} @offsets if $pregap;
print ((join ',',@offsets),"\n") if $debug;
#print Dumper \@offsets ,"\n";

use MusicBrainz::DiscID;

my $discid = MusicBrainz::DiscID->new();
#print join(';',1,$offsets[-1],@offsets[0..$#offsets-1]),"\n";
$discid->put(1,$offsets[-1],@offsets[0..$#offsets-1]);
#print "DiscID: " . $discid->id() . "\n";

my $url='http://musicbrainz.org/ws/2/discid/'. $discid->id() .'?inc=artists+labels+recordings';

use LWP::Simple;
use XML::Simple;
print "http://musicbrainz.org/cdtoc/" . $discid->id() . "\n";
my $discXML = get($url) or
    die "Диск не найден по идентификатору!\n";
my $discinfo = XMLin( $discXML );
print Dumper $discinfo if $debug;
die "диск соответствует нескольким релизам, ограничение демоверсии!\n"
        if $discinfo->{disc}->{'release-list'}->{count} != 1;
my $release = $discinfo->{disc}->{'release-list'}->{'release'};
die "в релизе более одного диска, ограничение демоверсии!\n\n"
    if $release->{'medium-list'}->{count} != 1;
print "имя альбома:\n" . $cue->{album} . '|' . $release->{title} . "\n"
    if $release->{title} ne $cue->{album};
my $tracklist = $release->{'medium-list'}->{medium}->{'track-list'};
die "различается количество композиций!\n\n"
    if $tracklist->{count} != scalar(@{$cue->{tracks}});
print $release->{id},"\n";
for (0..$#{$tracklist->{track}})
{
    my $title_from_cue = $cue->{tracks}->[$_]->{title};
    my $title_from_mb = $tracklist->{track}->[$_]->{recording}->{title};
#print ;
    print "название " . ($_+1) . " трека:\n" . $title_from_cue . '|' . $title_from_mb . "\n"
        if $title_from_mb ne $title_from_cue;
}

END {
    print "\n\n";
    sleep(5);
}
