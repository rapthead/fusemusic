package MusicDB;

use Rose::DB;
our @ISA = qw(Rose::DB);

__PACKAGE__->use_private_registry;

__PACKAGE__->register_db(
    domain   => MusicDB->default_domain,
    type     => MusicDB->default_type,
    driver   => 'sqlite',
    database => $ENV{'HOME'}.'/play_stat.db',
);

sub change_db_path {
    my $self = shift;
    my $db_path = shift;

    print $db_path, "\n";
    __PACKAGE__->register_db(
        domain   => 'custom',
        type     => 'custom',
        driver   => 'sqlite',
        database => $db_path,
    );

    MusicDB->default_domain('custom');
    MusicDB->default_type('custom');
};

sub init_objects {
    eval  { require MusicDB::Object; 1; }
    or do { die "$@\n"; };
}

1;
