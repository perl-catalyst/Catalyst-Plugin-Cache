#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan';

use Scalar::Util qw/refaddr/;

use ok "Catalyst::Plugin::Cache";

{
    package MockApp;
    use base qw/Catalyst::Plugin::Cache/;

    my %config = (
        cache => {
            profiles => {
                foo => {
                    bah => "foo",
                },
                bar => bless( {}, "SomeClass" ),
            },
        },
    );
    sub config { \%config };

    package SomeClass;
    sub get {}
    sub set {}
    sub remove {}
}

MockApp->setup;
my $c = bless {}, "MockApp";

MockApp->register_cache_backend( default => bless({}, "SomeClass") );

can_ok( $c, "curry_cache" );
can_ok( $c, "get_preset_curried" );

isa_ok( $c->cache, "Catalyst::Plugin::Cache::Curried" );

is( refaddr($c->cache), refaddr($c->cache), "default cache is memoized, so it is ==");

isa_ok( $c->cache("foo"), "Catalyst::Plugin::Cache::Curried", "cache('foo')" );

is_deeply( $c->cache("foo")->meta, [ bah => "foo" ], "meta is in place" ); 

is( refaddr( $c->cache("bar") ), refaddr( $c->cache("bar") ), "since bar is hard coded as an object it's always the same" );

