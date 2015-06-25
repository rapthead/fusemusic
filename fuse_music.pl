#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use Data::Dumper;
use Fuse;
use File::Basename;
use Getopt::Long;
use FileHandle;
use POSIX qw(ENOENT EISDIR);
use CHI;
             
use lib "$FindBin::RealBin/lib";
use Flac::TieFilehandle;
use MusicDB;

my $dbpath='';
my $musiclib = $ENV{'HOME'}.'/MUSIC/lossless/';
my $mountpoint = $ENV{'HOME'}."/FUSE_MUSIC/";
my $debug = 0;
GetOptions ("musiclib=s" => \$musiclib, "mountpoint=s" => \$mountpoint,
    "debug" => \$debug, "dbpath" => \$dbpath);

if ($dbpath) { MusicDB->change_db_path( $dbpath ); }
MusicDB->init_objects;

printf "musiclib=%s mountpoint=%s dbpath=%s\n", $musiclib, $mountpoint, $dbpath 
    if $debug;

our $cache = CHI->new( driver => 'Memory', global => 1 );
sub fat_restrict { (my $str = shift) =~ tr#]["\/:<>?*|#_#; return $str; }

# here is where you got new metainfo
sub getMeta {
    my $uri = shift;

    print "getMeta $uri\n" if $debug;

    my $track = Track->new('uri' => $uri);
    $track->load(with => [ 'album.artist' ]);
    my $album = $track->album;
    my $artist = $album->artist;

    my $taghash = {};
    $taghash->{'ALBUMARTIST'} = $artist->name;
    $taghash->{'ALBUM'}       = $album->title;
    $taghash->{'DATE'}        = $album->date->year();

    $taghash->{'TITLE'}       = $track->title;
    $taghash->{'TRACKNUMBER'} = $track->track_num;
    $taghash->{'ARTIST'}      = $track->track_artist || $artist->name;
    $taghash->{'DISC'}        = $track->disc;

    $taghash->{'REPLAYGAIN_REFERENCE_LOUDNESS'}= '89.0 dB';
    $taghash->{'REPLAYGAIN_ALBUM_GAIN'}        = $album->rg_peak;
    $taghash->{'REPLAYGAIN_ALBUM_PEAK'}        = $album->rg_gain;
    $taghash->{'REPLAYGAIN_TRACK_GAIN'}        = $track->rg_peak;
    $taghash->{'REPLAYGAIN_TRACK_PEAK'}        = $track->rg_gain;

    $taghash->{'MUSICBRAINZ_TRACKID'}      = 'MY_'.$track->track_id;

    while ( my ( $key, $val ) = each %$taghash ) {
        delete $taghash->{$key} if not defined $val;
    }

    $taghash->{'REPLAYGAIN_ALBUM_GAIN'} .= ' db'
        if $taghash->{'REPLAYGAIN_TRACK_GAIN'};

    $taghash->{'REPLAYGAIN_TRACK_GAIN'} .= ' db'
        if $taghash->{'REPLAYGAIN_TRACK_GAIN'};

    return $taghash;
}

sub rootdirlist {
    return $cache->compute('rootdirlist', undef, sub {
        my %albumlist;
        my $albums = Album::Manager->get_albums_iterator(
            require_objects => [ 'artist' ],
            sort_by => [ 'artist.name', 'title' ]
        );
        while(my $album = $albums->next)
        { 
            my $dirname = fat_restrict(join('–', $album->artist->name, $album->date->year(), $album->title));
            $albumlist{$dirname} = $album->album_id;
        }
        return %albumlist;
    });
}

sub tracklist {
    my %files;
    my $album = Album->new('album_id' => shift);
    $album->load( with => [ 'tracks' ]);
    foreach my $track (@{$album->tracks}) {
        my $filename = fat_restrict(sprintf '%02d-%s.flac', $track->track_num, $track->title);
        $files{$filename} = $track->uri if $track->uri;
    }
    return %files;
}

sub getUri {
    (my $path = shift) =~ s#^/##;
    my $dirname = basename(dirname($path));
    my $filename = basename($path);
    print "getUri $path\n" if $debug;

    my %list = rootdirlist;
    if (my $album_id = $list{$dirname}) {
        my %tracklist = tracklist($album_id);
        return $tracklist{$filename};
    }
}

sub findOrig {
    print "findOrig\n" if $debug;
    return $musiclib.getUri(shift);
}

sub getdir {
    (my $path = shift) =~ s#^/##;
    print "getDir $path\n" if $debug;
    my @names;

    my %list = rootdirlist;
    if ($path eq '') { @names = keys %list; } 
    else {
        if (my $album_id = $list{$path}) {
            my %tracklist = tracklist($album_id);
            @names = keys %tracklist;
        }
    }
    return (@names, 0);
}

sub getattr {
    (my $path = shift) =~ s#^/##;
    print STDERR "getattr $path\n" if $debug;

    return $cache->compute("attributes\0$path", '5 min', sub {
        my @attrs;
        my %list = rootdirlist;
        if ($list{$path} or $path eq '') {
            @attrs = (
                2056, #dev
                0, #ino
                040555, #mode
                1, #nlink
                0, #uid
                0, #gid
                0, #rdev
                1, #size
                0, #int(rand(3600))*86400, #atime
                int(rand(3600))*86400, #mtime
                0, #int(rand(3600))*86400, #ctime
                0, #blksize
                0  #blocks
            );
        }
        else {
            # TODO
            my $flacfile = findOrig($path);
            return 0 if (! -f $flacfile);
            my $uri = getUri($path);
            my $flh;
            { no warnings;
            $flh = *FLFL; }
            my %info;
            my $newMeta = getMeta($uri);
            my $size = (stat($flacfile))[7];
            if ($newMeta) {
                tie *$flh, "TieFilehandle", $flacfile, $newMeta, \%info;
                $size = $size - $info{'old_vorbis_length'} + $info{'new_vorbis_length'};
            }
            @attrs = (
                2056, #dev
                0, #ino
                0100555, #mode
                1, #nlink
                0, #uid
                0, #gid
                0, #rdev
                $size, #size
                0, #atime
                0, #mtime
                0, #ctime
                0, #blksize
                0  #blocks
            );
            close $flh;
        }
	#print Dumper \@attrs;
        return @attrs;
    });
}

## TODO: директории доступные только для чтения
sub open {
    my $path = shift;
    my $file = findOrig($path);
    my $uri = getUri($path);
    print STDERR "open $path\n" if $debug;

    return -ENOENT() unless $file;
    return -EISDIR() if -d $file;

    my $flacfile = ($file =~ m/.*\.flac$/)?$file:'';

    my $fh;
    if ($flacfile and (my $new_taghash = getMeta($uri))) {
        $fh = FileHandle->new;
        tie *$fh, "TieFilehandle", $flacfile, $new_taghash;
    }
    else {
        open $fh, "<", $file;
        binmode $fh;
    }
    return 0, $fh;
}
#
sub read {
    my $fuse_path = shift;

    print "read $fuse_path\n" if $debug;

    my ( $bytes, $offset, $fh ) = @_;
    my $buffer;
    # учесть offset
    seek( $fh, $offset, 0);
    my $status = read( $fh, $buffer, $bytes);#, $offset );
    if ($status > 0) {
        return $buffer;
    }
    return $status;
}

sub release {
    my $path = findOrig(shift);

    print "close $path\n" if $debug;

    my ( $flags, $fh) = @_;
    close($fh);
}

$SIG{USR1} = sub { $cache->clear(); };

print STDERR "init complete\n";
Fuse::main(
    #debug       => $debug,
    mountpoint  => $mountpoint,
    mountopts   => 'allow_other',
    getdir      => \&getdir,
    getattr     => \&getattr,
    threaded    => 0,
    open        => \&open,
    read        => \&read,
    release     => \&release
);
