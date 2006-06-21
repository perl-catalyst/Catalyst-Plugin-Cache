#!/usr/bin/perl

package Catalyst::Plugin::Cache;
use base qw/Class::Data::Inheritable Class::Accessor::Fast/;

use strict;
use warnings;

use Scalar::Util ();
use Catalyst::Utils ();
use Carp ();
use NEXT;

use Catalyst::Plugin::Cache::Curried;

__PACKAGE__->mk_classdata( "_cache_backends" );
__PACKAGE__->mk_accessors( "_default_curried_cache" );

sub setup {
    my $app = shift;

    # set it once per app, not once per plugin,
    # and don't overwrite if some plugin was wicked
    $app->_cache_backends({}) unless $app->_cache_backends;

    my $ret = $app->NEXT::setup( @_ );

    $app->setup_cache_backends;

    $ret;
}

sub get_default_cache_backend_config {
    my ( $app, $name ) = @_;
    $app->config->{cache}{backend} || $app->get_cache_backend_config("default");
}

sub get_cache_backend_config {
    my ( $app, $name ) = @_;
    $app->config->{cache}{backends}{$name};
}

sub setup_cache_backends {
    my $app = shift;

    # give plugins a chance to find things for themselves
    $app->NEXT::setup_cache_backends;

    foreach my $name ( keys %{ $app->config->{cache}{backends} } ) {
        next if $app->get_cache_backend( $name );
        $app->setup_generic_cache_backend( $name, $app->get_cache_backend_config( $name ) || {} );
    }

    if ( !$app->get_cache_backend("default") ) {
        local $@;
        eval { $app->setup_generic_cache_backend( default => $app->get_default_cache_backend_config || {} ) };
    }
}

sub default_cache_store {
    my $app = shift;
    $app->config->{cache}{default_store} || $app->guess_default_cache_store;
}

sub guess_default_cache_store {
    my $app = shift;

    my @stores = map { /Cache::Store::(.*)$/ ? $1 : () } $app->registered_plugins;

    if ( @stores == 1 ) {
        return $stores[0];
    } else {
        Carp::croak "You must configure a default store type unless you use exactly one store plugin.";
    }
}

sub setup_generic_cache_backend {
    my ( $app, $name, $config ) = @_;
    my %config = %$config;

    if ( my $class = delete $config{class} ) {
        $app->setup_cache_backend_by_class( $name, $class, %config );
    } elsif ( my $store = delete $config->{store} || $app->default_cache_store ) {
        my $method = lc("setup_${store}_cache_backend");

        Carp::croak "You must load the $store cache store plugin (if it exists). ".
        "Please consult the Catalyst::Plugin::Cache documentation on how to configure hetrogeneous stores."
            unless $app->can($method);

        $app->$method( $name, %config );
    } else {
        $app->log->warn("Couldn't setup the cache backend named '$name'");
    }
}

sub setup_cache_backend_by_class {
    my ( $app, $name, $class, @args ) = @_;
    Catalyst::Utils::ensure_class_loaded( $class );
    $app->register_cache_backend( $name => $class->new( @args ) );
}

# end of spaghetti setup DWIM

sub cache {
    my ( $c, @meta ) = @_;

    if ( @meta == 1 ) {
        my $name = $meta[0];
        return ( $c->get_preset_curried($name) || $c->get_cache_backend($name) );
    } elsif ( !@meta ) {
        # be nice and always return the same one for the simplest case
        return ( $c->_default_curried_cache || $c->_default_curried_cache( $c->curry_cache( @meta ) ) );
    } else {
        return $c->curry_cache( @meta );
    }
}

sub construct_curried_cache {
    my ( $c, @meta ) = @_;
    return $c->curried_cache_class( @meta )->new( @meta );
}

sub curried_cache_class {
    my ( $c, @meta ) = @_;
    $c->config->{cache}{curried_class} || "Catalyst::Plugin::Cache::Curried";
}

sub curry_cache {
    my ( $c, @meta ) = @_;
    return $c->construct_curried_cache( $c, $c->_cache_caller_meta, @meta );
}

sub get_preset_curried {
    my ( $c, $name ) = @_;

    if ( ref( my $preset = $c->config->{cache}{profiles}{$name} ) ) {
        return $preset if Scalar::Util::blessed($preset);

        my @meta = ( ( ref $preset eq "HASH" ) ? %$preset : @$preset );
        return $c->curry_cache( @meta );
    }

    return;
}

sub get_cache_backend {
    my ( $c, $name ) = @_;
    $c->_cache_backends->{$name};
}

sub register_cache_backend {
    my ( $c, $name, $backend ) = @_;

    no warnings 'uninitialized';
    Carp::croak("$backend does not look like a cache backend - "
    . "it must be an object supporting get, set and remove")
        unless eval { $backend->can("get") && $backend->can("set") && $backend->can("remove") };

    $c->_cache_backends->{$name} = $backend;
}

sub unregister_cache_backend {
    my ( $c, $name ) = @_;
    delete $c->_cache_backends->{$name};
}

sub default_cache_backend {
    my $c = shift;
    $c->get_cache_backend( "default" ) || $c->temporary_cache_backend;
}

sub temporary_cache_backend {
    my $c = shift;
    die "FIXME - make up an in memory cache backend, that hopefully works well for the current engine";
}

sub _cache_caller_meta {
    my $c = shift;

    my ( $caller, $component, $controller );
    
    for my $i ( 0 .. 15 ) { # don't look to far
        my @info = caller(2 + $i) or last;

        $caller     ||= \@info unless $info[0] =~ /Catalyst::Plugin::Cache/;
        $component  ||= \@info if $info[0]->isa("Catalyst::Component");
        $controller ||= \@info if $info[0]->isa("Catalyst::Controller");
    
        last if $caller && $component && $controller;
    }

    return (
        'caller'   => $caller,
        component  => $component,
        controller => $controller,
    );
}

# this gets a shit name so that the plugins can override a good name
sub choose_cache_backend_wrapper {
    my ( $c, @meta ) = @_;

    Carp::croak("meta data must be an even sized list") unless @meta % 2 == 0;

    my %meta = @meta;

    unless ( exists $meta{'caller'} ) {
        my %caller = $c->_cache_caller_meta;
        @meta{keys %caller} = values %caller;
    }
    
    # allow the cache client to specify who it wants to cache with (but loeave room for a hook)
    if ( exists $meta{backend} ) {
        if ( Scalar::Util::blessed($meta{backend}) ) {
            return $meta{backend};
        } else {
            return $c->get_cache_backend( $meta{backend} ) || $c->default_cache_backend;
        }
    };
    
    if ( my $chosen = $c->choose_cache_backend( %meta ) ) {
        $chosen = $c->get_cache_backend( $chosen ) unless Scalar::Util::blessed($chosen); # if it's a name find it
        return $chosen if Scalar::Util::blessed($chosen); # only return if it was an object or name lookup worked

        # FIXME
        # die "no such backend"?
        # currently, we fall back to default
    }
    
    return $c->default_cache_backend;
}

sub choose_cache_backend { shift->NEXT::choose_cache_backend( @_ ) } # a convenient fallback

sub cache_set {
    my ( $c, $key, $value, @meta ) = @_;
    $c->choose_cache_backend_wrapper( key =>  $key, value => $value, @meta )->set( $key, $value );
}

sub cache_get {
    my ( $c, $key, @meta ) = @_;
    $c->choose_cache_backend_wrapper( key => $key, @meta )->get( $key );
}

sub cache_remove {
    my ( $c, $key, @meta ) = @_;
    $c->choose_cache_backend_wrapper( key => $key, @meta )->remove( $key );
}

__PACKAGE__;

__END__

=pod

=head1 NAME

Catalyst::Plugin::Cache - 

=head1 SYNOPSIS

	use Catalyst qw/
        Cache
    /;

    # configure a backend or use a store plugin 
    __PACKAGE__->config( cache => {
        backend => {
            class => "Cache::Bounded",
            # ... params ...
        },
    });

    # ... in a controller

    sub foo : Local {
        my ( $self, $c, $id ) = @_;

        my $cache = $c->cache;

        my $result;

        unless ( $result = $cache->get( $id ) ) {
            # ... calulate result ...
            $c->cache->set( $id, $result );
        }
    };

=head1 DESCRIPTION

This plugin allows you to use a very simple configuration API without losing
the possibility of flexibility when you need it later.

Amongst it's features are support for multiple backends, segmentation based on
component or controller, keyspace partitioning and so forth, in various sub
plugins.

=head1 CONFIGURATION

  $c->config->{cache} = {
    backend => '',
  };

All configuration parameters should be provided in a hash reference under the
C<cache> key in the C<config> hash.

=over 4

=item class

Load an entire set of Caching modules.

=item backend

The specific backend you want to use.

=item backends

A hashref with backend names as keys, and module names as values. One of these
should have the key "default" to indicate the default backend.

=item default_store

The store you are using. This must be supplied if you have loaded multiple
store plugins.

=item curried_class

The currying class you are using, defaults to L<Catalyst::Plugin::Cache::Curried>.

=item profiles

Supply your own predefined profiles for cache namespacing.
 

=back

=head1 TERMINOLOGY

=over 4

=item backend

An object that responds to the methods detailed in
L<Catalyst::Plugin::Cache::Backend> (or more).

=item store

A plugin that provides backends of a certain type. This is a bit like a factory.

=item cache

Stored key/value pairs of data for easy re-access.

=item curried cache

  my $cache = $c->cache(type => 'thumbnails');
  $cache->set('pic01', $thumbnaildata);

A cache which has been pre-configured with a particular set of namespacing
data. In the example the cache returned could be one specifically tuned
for storing thumbnails.

An object that responds to C<get>, C<set> and C<remove>, and will automatically
add meta data to calls to C<< $c->cache_get >>, etc.

=back

=cut


