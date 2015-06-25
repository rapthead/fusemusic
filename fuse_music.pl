#!/usr/bin/env perl
use FindBin;

use strict;
use warnings;
use Data::Dumper;
use Fuse;
use File::Basename;
use Getopt::Long;
use FileHandle;
use POSIX qw(ENOENT EISDIR);
             
use lib "$FindBin::RealBin/lib";
use CueParse;
use Flac::TieFilehandle;

use DBI;

my $musiclib = $ENV{'HOME'}.'/MUSIC/lossless/';
my $mountpoint = $ENV{'HOME'}."/FUSE_MUSIC/";
my $dbpath = $ENV{'HOME'}."/play_stat.db.bak2";
my $debug = 0;
GetOptions ("musiclib=s" => \$musiclib, "mountpoint=s" => \$mountpoint,
    "debug" => \$debug, "dbpath" => \$dbpath);

printf "musiclib=%s mountpoint=%s dbpath=%s\n", $musiclib, $mountpoint, $dbpath 
    if $debug;
#if ($debug) {
	#print $musiclib, $mountpoint, $dbpath;
#}

my $db = DBI->connect(
    "dbi:SQLite:dbname=$dbpath",
    "",
    "",
    { RaiseError => 1, AutoCommit => 1 }
);
$db->func( 'fat_restrict', 1, sub { (my $str = shift) =~ tr#]["\/:<>?*|#_#; return $str; }, 'create_function' );

my $get_meta = $db->prepare(<<'__SQL_END__');
SELECT 
    track.title, track.track_num, track.track_artist, track.disc,
    album.title as album_title, album.orig_year, album.release_year,
    track.track_id as track_id,
    artist.name,
    track.uri
FROM track
JOIN album ON album.album_id = track.album_id
JOIN artist ON artist.artist_id = album.artist_id
WHERE track.uri = ?
__SQL_END__

my $dir_list_sql = <<'__SQL_END__';
SELECT  fat_restrict( artist.name || '-' || album.release_year || '-' || album.title) as dir,
        album.album_id as album_id
FROM album
JOIN artist ON artist.artist_id = album.artist_id
WHERE album.isactive == 1
__SQL_END__
my $dir_list = $db->prepare($dir_list_sql);
my $get_album_id_by_dir = $db->prepare($dir_list_sql.' and dir = ?');

my $file_list_by_dir_name_sql = <<"__SQL_END__";
SELECT fat_restrict(substr('0' || track.track_num, length(track.track_num)) || '-' || track.title || '.flac') as file,
        track.album_id as album_id,
        track.uri as track_uri
FROM ( $dir_list_sql and dir = ?) as dir_list_subquerry
JOIN track ON dir_list_subquerry.album_id = track.album_id
__SQL_END__
my $file_list = $db->prepare($file_list_by_dir_name_sql);

my $uri_by_album_id_sql = <<"__SQL_END__";
SELECT fat_restrict(substr('0' || track.track_num, length(track.track_num)) || '-' || track.title || '.flac') as file,
        track.album_id as album_id,
        track.uri as track_uri
FROM track
WHERE track.album_id = ? AND file = ?
__SQL_END__
my $uri_by_album_id = $db->prepare($uri_by_album_id_sql);

# here is where you got new metainfo
sub getMeta {
    my $uri = shift;

    print "getMeta $uri\n" if $debug;

    $get_meta->execute($uri);
    if (my $row = $get_meta->fetchrow_hashref) {
        my $taghash = {};
        $taghash->{'ALBUMARTIST'} = $row->{'name'}        if $row->{'name'}        ;
        $taghash->{'ALBUM'}       = $row->{'album_title'} if $row->{'album_title'} ;
        $taghash->{'TITLE'}       = $row->{'title'}       if $row->{'title'}       ;
        $taghash->{'TRACKNUMBER'} = $row->{'track_num'}   if $row->{'track_num'}   ;
        $taghash->{'ARTIST'}      = $row->{'track_artist'}if $row->{'track_artist'};
        $taghash->{'DISC'}        = $row->{'disc'}        if $row->{'disc'}        ;
        $taghash->{'DATE'}        = $row->{'orig_year'}   if $row->{'orig_year'}   ;

        $taghash->{'DATE'}        = $taghash->{'DATE'}.$row->{'album.release_year'} if $row->{'album.release_year'};
        $taghash->{'ARTIST'}      = $row->{'name'} unless $taghash->{'ARTIST'};

        $taghash->{'MUSICBRAINZ_TRACKID'}      = 'MY_'.$row->{'track_id'};

        return $taghash;
    }
    else {
        return;
    }
}

{
    my @albums_id_array;
    sub getUri {
        my $path = shift;

        print "getUri $path\n" if $debug;

        my $dirname = basename(dirname($path));
        my $basename = basename($path);

        # TODO: сделать массивом и ограничить размер
        my $album_id;
        my %albums_id_hash = map { $_->{'dir'} => $_->{'id'} } @albums_id_array;
        unless ($album_id = $albums_id_hash{$dirname}) {
            $get_album_id_by_dir->execute($dirname);
            $album_id = $get_album_id_by_dir->fetchrow_hashref->{'album_id'};
            $albums_id_hash{$dirname} = $album_id;

            unshift(@albums_id_array, { 'dir' => $dirname, 'id' => $album_id} );
            @albums_id_array = @albums_id_array[0..49] if scalar(@albums_id_array) > 50;
        }
        $uri_by_album_id->execute($album_id, $basename);
        my $row = $uri_by_album_id->fetchrow_hashref;
        return $row->{'track_uri'};
    }
}

sub findOrig {
    print "findOrig\n" if $debug;
    return $musiclib.getUri(shift);
}

sub getdir {
    print "getDir\n" if $debug;
    my $dirname = shift;

    my @subdirs;
    if ($dirname eq '/') {
        $dir_list->execute();
        while (my @row = $dir_list->fetchrow_array) {
                push(@subdirs,$row[0]);
        }
    } 
    else {
        $file_list->execute(basename($dirname));
        while (my $row = $file_list->fetchrow_hashref) {
                push(@subdirs,$row->{'file'}) if $row->{'track_uri'} && -e $musiclib.$row->{'track_uri'};
        }
    }

    return (@subdirs, 0);
}

{
    my $prev_path = undef;
    my @prev_attrs = undef;

    sub getattr {
        my $path = shift;
        my @attrs;

        if ($path eq $prev_path) {
            print "attrs from cache\n" if $debug;
            return @prev_attrs;
        }
        else {
            $prev_path = $path;
            print "getattr $path\n" if $debug;
        }

        unless ($path =~ m/.*\.flac$/) {
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
            my $flacfile = findOrig($path);
            return 0 if (! -e $flacfile);
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

        @prev_attrs = @attrs;
	print Dumper \@attrs;
        return @attrs;
    }
}
#
## TODO: директории доступные только для чтения
sub open {
    my $path = shift;
    my $file = findOrig($path);
    my $uri = getUri($path);

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
