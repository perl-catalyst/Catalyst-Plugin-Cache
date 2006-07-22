use strict;
use Module::Build;

my $build = Module::Build->new(
    create_makefile_pl => 'traditional',
    license            => 'perl',
    module_name        => 'Catalyst::Plugin::Cache',
    requires           => {
        'perl'              => '5.8.1',
        'Catalyst'          => '5.7',
        'Storable'          => 0,
        'Test::Deep'        => 0,
        'Test::More'        => 0,
        'Test::Exception'   => 0,
        'Task::Weaken'      => 0,
    },
    create_readme => 1,
    sign          => 1,
);
$build->create_build_script;

