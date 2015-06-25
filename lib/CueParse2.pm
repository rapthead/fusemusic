#!/usr/bin/perl
package CueParse2;
use strict;
use Carp;
use File::Basename;
use Data::Dumper;
@CueParse2::CUESHEET_COMMANDS = qw(
    CATALOG
    CDTEXTFILE
    FILE
    FLAGS
    INDEX
    ISRC
    PERFORMER
    POSTGAP
    PREGAP
    REM
    SONGWRITER
    TITLE
    TRACK
);
# первая строка - используемые вторая на всякий случай
@CueParse2::ALBUM_COMMANDS_ORDER = qw(
    REM CATALOG PERFORMER TITLE SONGWRITER CDTEXTFILE
    FILE FLAGS INDEX ISRC POSTGAP PREGAP TRACK
);
# первая строка - используемые вторая на всякий случай
@CueParse2::TRACK_COMMANDS_ORDER = qw(
    TRACK TITLE PERFORMER SONGWRITER ISRC FLAGS REM PREGAP INDEX POSTGAP
    CATALOG CDTEXTFILE FILE
);

BEGIN {
    use Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(parseCue parseCueRaw writeCueRaw unquote);
}

my $all_commands_alt = join "|",@CueParse2::CUESHEET_COMMANDS;
my $all_commands_re = qr/$all_commands_alt/;

sub parseline {
    my ($curline, $meta, $files) = @_;

    $meta = {}
        if (!defined $meta);
    if ( $curline =~ m/^\s*($all_commands_re)\s+(.*?)\s*$/o ) {
        my ($command, $value) = ($1, $2);

        if ($command eq 'REM') {
            $meta->{$command} = []
                if (! defined $meta->{$command});
            push @{$meta->{$command}}, $value;
        }
        elsif ($command eq 'INDEX') {
            $meta->{$command} = []
                if (! defined $meta->{$command});
            $value =~ m/(\d{2})\s+(\d{2}:\d{2}:\d{2})/ || die "неверный синтаксис команды INDEX\n";
            $meta->{$command}->[$1+0] = {
                'value' => $2,
                'fileindex' => $#{ $files }
            };
        }
        elsif ($command eq 'FILE') {
            push @{$files}, $value;
        }
        elsif ($command eq 'TRACK' && $meta->{$command}) {
            return -1;
        }
        else {
            $meta->{$command} = $value
        }
        return $command;
    }
    else {
        return 0;
    }
}

sub parseCueRaw($) {
    my $cuefile = shift;
    open (CUE, "<", $cuefile) or die "$cuefile: $!";
    my @cuelines = <CUE>;

    my ($i, $line, %meta) = (0);
    $meta{'album'} = {};
    $meta{'tracks'} = [];
    $meta{'files'} = [];
    while ( $line = $cuelines[$i++] ) {
        if ($line =~ m/^\s*TRACK/o) { $i--; last; }
        parseline($line, $meta{'album'}, $meta{'files'}) || die "неизвестный идентификатор в cue: ".($i+1)." строка\n";
    }

    my $tracknum = 0;
    my $trackMeta = {};
    while ( $line = $cuelines[$i]) {
        my $status = 
            parseline($line, $trackMeta, $meta{'files'}) || die "неизвестный идентификатор в cue: ".($i+1)." строка\n";
        if ($status == -1 || $#cuelines == $i) {
            if (!defined $trackMeta->{'INDEX'}) {
                $trackMeta->{'INDEX'} =
                    [
                        undef,
                        {
                            'value' => '00:00:00',
                            'fileindex' => $#{ $meta{'files'} }
                        }
                    ];
            }
            push @{ $meta{'tracks'} }, $trackMeta;

            $trackMeta = {};
            redo if ($#cuelines != $i);
        }
        $i++;
    }

    close CUE;
    return \%meta;
}

sub writeCueRaw($) {
    my $cuehash = shift;
    # REM CATALOG PERFORMER TITLE SONGWRITER CDTEXTFILE
    foreach my $albumkey (@CueParse2::ALBUM_COMMANDS_ORDER) {
        next if (!defined $cuehash->{album}->{$albumkey});
        my $val_ref = $cuehash->{album}->{$albumkey};
        if(ref($val_ref) ne 'ARRAY'){
            printf "%s %s\n", $albumkey, $val_ref;
        }
        else {
            foreach my $val (@{$val_ref}) {
                printf "%s %s\n", $albumkey, $val;
            }
        }
    }

    # TRACK TITLE PERFORMER ISRC FLAGS REM PREGAP INDEX POSTGAP
    foreach my $track_index (keys @{$cuehash->{tracks}}) {
        my $track = $cuehash->{tracks}->[$track_index];
        my $indexes = delete $track->{INDEX};

        if (!defined $indexes->[0] && defined $indexes->[1]) {
            printf "%s %s\n", 'FILE', delete $cuehash->{files}->[$indexes->[1]->{'fileindex'}]
        }

        $track->{TRACK} || die "нет команды TRACK для $track_index трека";
        printf "  %s %s\n", 'TRACK', delete $track->{TRACK};

        foreach my $trackkey (@CueParse2::TRACK_COMMANDS_ORDER) {
            my $val_ref = $track->{$trackkey};
            next if (!defined $val_ref);
            if(ref($val_ref) ne 'ARRAY'){
                printf "    %s %s\n", $trackkey, $val_ref;
            }
            else {
                foreach my $val (@{$val_ref}) {
                    printf "    %s %s\n", $trackkey, $val;
                }
            }
        }

        foreach my $index_key (sort keys @{$indexes}) {
            my $filestring;
            printf "%s %s\n", 'FILE', $filestring
                if ($filestring = delete $cuehash->{files}->[$indexes->[$index_key]->{'fileindex'}]);
            printf "    %s %02u %s\n", 'INDEX', $index_key, $indexes->[$index_key]->{'value'}
                if ($indexes->[$index_key]->{'value'});
        }
    }
}

sub unquote($) {
    my $value = shift;
    $value =~ s/''/"/g if ($value =~ s/^"|"$//g);
    return $value;
}

sub prepareData($$) {
    my ($cueObj, $type) = @_;
    $cueObj->{TITLE} = unquote($cueObj->{TITLE});
    $cueObj->{PERFORMER} = unquote($cueObj->{PERFORMER});

    my %rems;
    foreach my $rem (@{$cueObj->{REM}}) {
        $rem =~ s/^(\w+)\s+//;
        $rems{$1} = unquote($rem);
    }
    $cueObj->{REM} = \%rems;

    if ($type eq 'track') {
        $cueObj->{TRACK} =~ /(\d+)\s+(\w+)/;
        $cueObj->{TRACK} = {
            'number' => $1+0,
            'datatype' => $2
        };
    }
}

sub parseCue($) {
    my $cueHashRaw;
    my $arg = shift;
    if (ref($arg) eq 'HASH') { $cueHashRaw = $arg; }
    else { $cueHashRaw = parseCueRaw($arg); }

    my $cueHash = $cueHashRaw;
    foreach my $file (@{$cueHash->{'files'}}) {
        $file =~ s/\s+(\w+)$//;
        my ($filename, $filetype) = (unquote($file), $1);
        $file = {
            'filename' => $filename,
            'filetype' => $filetype,
        }
    }

    prepareData($cueHash->{'album'}, 'album');
    foreach my $track (@{$cueHash->{'tracks'}}) {
        prepareData($track, 'track');
    }

    return $cueHash;
}

1;
