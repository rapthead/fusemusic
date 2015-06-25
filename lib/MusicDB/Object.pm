package MusicDB::Object;
use base qw(Rose::DB::Object);
use Rose::DB::Object::Helpers 'column_values_as_json';
#sub init_db { MusicDB->new }
sub init_db { MusicDB->new_or_cached }

package LogRecord;
use strict;
use base qw(MusicDB::Object);
#CREATE TABLE play_log (
#    track_id INTEGER NOT NULL,
#    time DATETIME NOT NULL,
#    source TINYINT,
#    UNIQUE ( track_id, time, source )
#    FOREIGN KEY (track_id) REFERENCES track(track_id)
#    ON DELETE RESTRICT
#);
#CREATE INDEX "play_log_foreign" ON "play_log" ("track_id" ASC);
__PACKAGE__->meta->setup
(
    table      => 'play_log',
    columns    => [
        track_id        => { type => 'integer', not_null => 1 },
        time            => { type => 'datetime', not_null => 1 },
        source          => { type => 'tinyint' },
    ],
    unique_keys => [ 'track_id', 'time', 'source' ],
    relationships =>
    [
        track =>
        {
            type       => 'many to one',
            class      => 'Track',
            column_map => { track_id => 'track_id' },
        },
    ],
);
__PACKAGE__->meta->make_manager_class('logrecords');

package Track;
use strict;
use base qw(MusicDB::Object);
#CREATE TABLE `track` (
#	`track_id`	INTEGER,
#	`album_id`	INT NOT NULL,
#	`track_num`	SMALLINT NOT NULL,
#	`title`	VARCHAR(255) NOT NULL,
#	`track_artist`	VARCHAR(255),
#	`length`	INT NOT NULL,
#	`disc`	SMALLINT,
#	`uri`	VARCHAR,
#	`rg_peak`	REAL,
#	`rg_gain`	REAL,
#	PRIMARY KEY(track_id)
#);
# CREATE INDEX "track_foreign" ON "track" ("album_id" ASC);
# CREATE INDEX "trakc_key" ON "track" ("track_id" ASC);

__PACKAGE__->meta->setup
(
    table      => 'track',
    columns    => [
        track_id        => { type => 'integer', primary_key => 1 },
        album_id        => { type => 'integer', not_null => 1 },
        track_num       => { type => 'smallint', not_null => 1 },
        title           => { type => 'varchar', length => 255, not_null => 1 },
        track_artist    => { type => 'varchar', length => 255 },
        length          => { type => 'integer', not_null => 1 },
        disc            => { type => 'smallint' },
        rg_peak         => { type => 'float' },
        rg_gain         => { type => 'float' },
        uri             => { type => 'varchar' },
    ],
    unique_keys => [ 'uri' ],
    relationships =>
    [
        album =>
        {
            type       => 'many to one',
            class      => 'Album',
            column_map => { album_id => 'album_id' },
        },
        logrecords =>
        {
            type       => 'one to many',
            class      => 'LogRecords',
            column_map => { track_id => 'track_id' },
        },
    ],
);
__PACKAGE__->meta->make_manager_class('tracks');


package Album;
use strict;
use base qw(MusicDB::Object);
#CREATE TABLE `album` (
#	`genre`	TEXT,
#	`isactive`	BOOLEAN,
#	`album_id`	INTEGER,
#	`artist_id`	INTEGER NOT NULL,
#	`title`	VARCHAR(255),
#	`date`	DATE,
#	`release_date`	DATE,
#	`mbid`	VARCHAR(36),
#	`rg_peak`	REAL,
#	`rg_gain`	REAL,
#	PRIMARY KEY(album_id)
#);
__PACKAGE__->meta->setup
(
    table      => 'album',
    columns    => [
        album_id        => { type => 'integer', primary_key => 1 },
        artist_id       => { type => 'integer', not_null => 1 },
        title           => { type => 'varchar', length => 255, not_null => 1 },
        date            => { type => 'date' },
        release_date    => { type => 'date' },
        genre           => { type => 'text' },
        rg_peak         => { type => 'float' },
        rg_gain         => { type => 'float' },
        mbid            => { type => 'varchar', length => 36 },
        isactive        => { type => 'boolean' },
    ],
    unique_keys => [ 'title', 'date', 'release_date' ],
    relationships =>
    [
        artist =>
        {
            type       => 'many to one',
            class      => 'Artist',
            column_map => { artist_id => 'artist_id' },
        },
        tracks =>
        {
            type       => 'one to many',
            class      => 'Track',
            column_map => { album_id => 'album_id' },
        },
    ],
);
__PACKAGE__->meta->make_manager_class('albums');

package Artist;
use strict;
use base qw(MusicDB::Object);
#CREATE TABLE artist (
#    artist_id INTEGER PRIMARY KEY,
#    name VARCHAR( 255 ) NOT NULL
#);
__PACKAGE__->meta->setup
(
    table      => 'artist',
    columns    => [
        artist_id      => { type => 'integer', primary_key => 1 },
        name           => { type => 'varchar', length => 255, not_null => 1 },
    ],
    unique_keys => [ 'name' ],
    relationships =>
    [
        albums =>
        {
            type       => 'one to many',
            class      => 'Album',
            column_map => { artist_id => 'artist_id' },
        },
    ],
);
__PACKAGE__->meta->make_manager_class('artists');

1;
