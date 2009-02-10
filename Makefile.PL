use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'         => 'Catalyst::Plugin::Cache',
    'VERSION_FROM' => 'lib/Catalyst/Plugin/Cache.pm',
    'PREREQ_PM'    => {
        'Catalyst'        => '5.7',
        'Storable'        => 0,
        'Task::Weaken'    => 0,
        'Test::Deep'      => 0,
        'Test::Exception' => 0,
        'Test::More'      => 0,
        'MRO::Compat'     => 0,
	'ok'              => 0,
   },
    'INSTALLDIRS' => 'site',
    'EXE_FILES'   => [],
    'PL_FILES'    => {},
    'SIGN'        => 1,
);
