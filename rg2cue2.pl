#!/usr/bin/perl
use strict;
use Data::Dumper;
use FindBin;
use lib "$FindBin::RealBin/lib";

use strict;
use CueParse2;

my $cueFile = shift;

sub getGainHash {
    my $re_trackinfo = qr/^(?<file>.+):(?<tag>.+)=(?<value>.*?)$/;
    my %rg_info = (
        'album' => {},
        'track' => {}
    );
    while (<>) {
        my %data;
        if (m/$re_trackinfo/) {
            if (ref $rg_info{track}->{$+{file}} ne ref $rg_info{track}->{$+{file}}) {
                $rg_info{track}->{$+{file}} = {};
            }

            if ($+{tag} eq 'REPLAYGAIN_TRACK_GAIN') {
                $rg_info{track}->{$+{file}}->{gain} = $+{value};
            }
            elsif ($+{tag} eq 'REPLAYGAIN_TRACK_PEAK') {
                $rg_info{track}->{$+{file}}->{peak} = $+{value};
            }
            elsif ($+{tag} eq 'REPLAYGAIN_ALBUM_GAIN') {
                $rg_info{album}->{gain} = $+{value};
            }
            elsif ($+{tag} eq 'REPLAYGAIN_ALBUM_PEAK') {
                $rg_info{album}->{peak} = $+{value};
            }
        }
    }
    return \%rg_info;
}

sub add_or_replace {
    my ($prefix, $arrayref, $value) = @_;
    # TODO: заменить regex на index
    @{$arrayref} = grep !/^$prefix/, @{$arrayref};
    push @{$arrayref}, $value;
}

my $gain_hash = getGainHash();

my $cue_hash = parseCueRaw($cueFile) or die "неверный $cueFile";

if ( $gain_hash->{album}->{gain} ) {
    if(ref($cue_hash->{album}->{REM}) ne 'ARRAY') { $cue_hash->{album}->{REM}=[] }
    add_or_replace('REPLAYGAIN_ALBUM_GAIN', $cue_hash->{album}->{REM}, 'REPLAYGAIN_ALBUM_GAIN '.$gain_hash->{album}->{gain});
}
if ( $gain_hash->{album}->{gain} ) {
    if(ref($cue_hash->{album}->{REM}) ne 'ARRAY') { $cue_hash->{album}->{REM}=[] }
    add_or_replace('REPLAYGAIN_ALBUM_PEAK', $cue_hash->{album}->{REM}, 'REPLAYGAIN_ALBUM_PEAK '. $gain_hash->{album}->{peak});
}

foreach my $filename (keys %{$gain_hash->{track}}) {
    my $gain_track = $gain_hash->{track}->{$filename};
    my $file_index = -1;
    foreach my $cur_index (keys @{$cue_hash->{files}}) {
        my $cur_file = $cue_hash->{files}->[$cur_index];
        if (index($cur_file, "\"$filename\"") == 0) {
            $file_index = $cur_index;
            last;
        }
    }

    if ($file_index != -1) {
        foreach my $track (@{$cue_hash->{tracks}}) {
            if ($track->{INDEX}->[1] and $track->{INDEX}->[1]->{fileindex} == $file_index) {
                if(ref($track->{REM}) ne 'ARRAY') { $track->{REM}=[] }
                add_or_replace('REPLAYGAIN_TRACK_GAIN', $track->{REM}, 'REPLAYGAIN_TRACK_GAIN '.$gain_track->{gain});
                add_or_replace('REPLAYGAIN_TRACK_PEAK', $track->{REM}, 'REPLAYGAIN_TRACK_PEAK '.$gain_track->{peak});
            }
        }
    }
    else {
        die "Файл $filename не найден в cue\n";
    }
}

#print Dumper $cue_hash;
writeCueRaw($cue_hash);
