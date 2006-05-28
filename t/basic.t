#!/usr/bin/perl

use strict;
use warnings;

use Test::More 'no_plan';
use Test::Exception;

use ok "Catalyst::Plugin::Cache";

{
    package MockApp;
    use base qw/Catalyst::Plugin::Cache/;

    package MemoryCache;
    use Storable qw/freeze thaw/;
    
    sub new { bless {}, shift }
    sub get { ${thaw($_[0]{$_[1]}) || return} };
    sub set { $_[0]{$_[1]} = freeze(\$_[2]) };
    sub delete { delete $_[0]{$_[1]} };
}

MockApp->setup;
my $c = bless {}, "MockApp";

can_ok( $c, "register_cache_backend" );
can_ok( $c, "unregister_cache_backend" );

MockApp->register_cache_backend( default => MemoryCache->new );
MockApp->register_cache_backend( moose => MemoryCache->new );

can_ok( $c, "cache" );

ok( $c->cache, "->cache returns a value" );

can_ok( $c->cache, "get" ); #, "rv from cache" );
can_ok( $c->cache("default"), "get" ); #, "default backend" );
can_ok( $c->cache("moose"), "get" ); #, "moose backend" );

ok( !$c->cache("lalalala"), "no lalala backend");

MockApp->unregister_cache_backend( "moose" );

ok( !$c->cache("moose"), "moose backend unregistered");


dies_ok {
    MockApp->register_cache_backend( ding => undef );
} "can't register invalid backend";

dies_ok {
    MockApp->register_cache_backend( ding => bless {}, "SomeClass" );
} "can't register invalid backend";



can_ok( $c, "default_cache_backend" );
is( $c->default_cache_backend, $c->cache, "cache with no args retrurns default" );

can_ok( $c, "choose_cache_backend_wrapper" );
can_ok( $c, "choose_cache_backend" );

can_ok( $c, "cache_set" );
can_ok( $c, "cache_get" );
can_ok( $c, "cache_delete" );

$c->cache_set( foo => "bar" );
is( $c->cache_get("foo"), "bar", "set" );

$c->cache_delete( "foo" );
is( $c->cache_get("foo"), undef, "delete" );

MockApp->register_cache_backend( elk => MemoryCache->new );

is( $c->choose_cache_backend_wrapper( key => "foo" ), $c->default_cache_backend, "choose default" );
is( $c->choose_cache_backend_wrapper( key => "foo", backend => "elk" ), $c->get_cache_backend("elk"), "override choice" );


$c->cache_set( foo => "gorch", backend => "elk" );
is( $c->cache_get("foo"), undef, "set to custom backend (get from non custom)" );
is( $c->cache_get("foo", backend => "elk"), "gorch", "set to custom backend (get from custom)" );

