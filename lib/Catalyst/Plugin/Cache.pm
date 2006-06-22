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

        $caller     ||= \@info unless $info[0] =~ /Plugin::Cache/;
        $component  ||= \@info if $info[0]->isa("Catalyst::Component");
        $controller ||= \@info if $info[0]->isa("Catalyst::Controller");
    
        last if $caller && $component && $controller;
    }

    my ( $caller_pkg, $component_pkg, $controller_pkg ) =
        map { $_ ? $_->[0] : undef } $caller, $component, $controller;

    return (
        'caller'   => $caller_pkg,
        component  => $component_pkg,
        controller => $controller_pkg,
        caller_frame     => $caller,
        component_frame  => $component,
        controller_frame => $controller,
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

Catalyst::Plugin::Cache - Flexible caching support for Catalyst.

=head1 SYNOPSIS

	use Catalyst qw/
        Cache
    /;

    # configure a backend or use a store plugin 
    __PACKAGE__->config->{cache}{backend} = {
        class => "Cache::Bounded",
        # ... params ...
    };

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

=head1 METHODS

=over 4

=item cache $profile_name

=item cache %meta

Return a curried object with meta data from $profile_name or as explicitly
specified.

If a profile by the name $profile_name doesn't exist but a backend object by
that name does exist, the backend will be returned instead, since the interface
for curried caches and backends is almost identical.

This method can also be called without arguments, in which case is treated as
though the %meta hash was empty.

See L</META DATA> for details.

=item curry_cache %meta

Return a L<Catalyst::Plugin::Cache::Curried> object, curried with %meta.

See L</META DATA> for details.

=item cache_set $key, $value, %meta

=item cache_get $key, %meta

=item cache_remove $key, %meta

These cache operations will call L<choose_cache_backend> with %meta, and then
call C<set>, C<get> or C<remove> on the resulting backend object.

=item choose_cache_backend %meta

Select a backend object. This should return undef if no specific backend was
selected - it's caller will handle getting C<default_cache_backend> on it's own.

This method is typically used by plugins.

=item get_cache_backend $name

Get a backend object by name.

=item default_cache_backend

Return the default backend object.

=item temporary_cache_backend

When no default cache backend is configured this method might return a backend
known to work well with the current L<Catalyst::Engine>. This is a stup.

=item 

=back

=head1 META DATA

=head2 Introduction

Whenever you set or retrieve a key you may specify additional meta data that
will be used to select a specific backend.

This metadata is very freeform, and the only key that has any meaning by
default is the C<backend> key which can be used to explicitly choose a backend
by name.

The C<choose_cache_backend> method can be overridden in order to facilitate
more intelligent backend selection. For example,
L<Catalyst::Plugin::Cache::Choose::KeyRegexes> overrides that method to select
a backend based on key regexes.

Another example is a L<Catalyst::Plugin::Cache::ControllerNamespacing>, which
that wraps backends in objects that perform key mangling, in order to keep
caches namespaced per controller.

However, this is generally left as a hook for larger, more complex
applications. Most configurations should make due 

The simplest way to dynamically select a backend is based on the L</Cache
Profiles> configuratrion.

=head2 Meta Data Keys

C<choose_cache_backend> is called with some default keys.

=over 4

=item key

Supplied by C<cache_get>, C<cache_set> and C<cache_remove>.

=item value

Supplied by C<cache_set>

=item caller

The package name of the innermost caller that doesn't match
C<qr/Plugin::Cache/>.

=item caller_frame

The entire C<caller($i)> frame of C<caller>.

=item component

The package name of the innermost caller who C<isa> L<Catalyst::Component>.

=item component_frame

This entire C<caller($i)> frame of C<component>.

=item controller

The package name of the innermost caller who C<isa> L<Catalyst::Controller>.

=item controller_frame

This entire C<caller($i)> frame of C<controller>.

=back

=head2 Meta Data Currying

In order to avoid specifying %meta over and over again you may call C<cache> or
C<curry_cache> with %meta once, and get back a B<curried cache object>. This
object responds to the methods C<get>, C<set> and C<remove>, by appending it's
captured meta data and delegating them to C<cache_get>, C<cache_set> and
C<cache_remove>.

This is simpler than it sounds.

Here is an example using currying:

    my $cache = $c->cache( %meta ); # cache is curried

    $cache->set( $key, $value );

    $cache->get( $key );

And here is an example without using currying:

    $c->cache_set( $key, $value, %meta );

    $c->cache_get( $key, %meta );

See L<Catalyst::Plugin::Cache::Curried> for details.

=head1 CONFIGURATION

    $c->config->{cache} = {
        ...
    };

All configuration parameters should be provided in a hash reference under the
C<cache> key in the C<config> hash.

=head2 Backend Configuration

Configuring backend objects is done by adding hash entries under the
C<backends> keys in the main config.

A special case is that the hash key under the C<backend> (singular) key of the
main config is assumed to be the backend named C<default>.

=over 4

=item class

Instantiate a backend from a L<Cache> compatible class. E.g.

    $c->config->{cache}{backends}{small_things} = {
        class    => "Cache::Bounded",
        interval => 1000,
        size     => 10000,
    };
    
    $c->config->{cache}{backends}{large_things} = {
        class => "Cache::Memcached::Mangaed",
        data  => '1.2.3.4:1234',
    };

The options in the hash are passed to the class's C<new> method.

The class will be C<required> as necessary during setup time.

=item store

Instrantiate a backend using a store plugin, e.g.

    $c->config->{cache}{backend} = {
        store => "FastMmap",
    };

Store plugins typically require less configuration because they are specialized
for L<Catalyst> applications. For example
L<Catalyst::Plugin::Cache::Store::FastMmap> will specify a default
C<share_file>, and additionally use a subclass of L<Cache::FastMmap> that can
also store non reference data.

The store plugin must be loaded.

=back

=head2 Cache Profiles

=over 4

=item profiles

Supply your own predefined profiles for cache metadata, when using the C<cache>
method.

For example when you specify

    $c->config->{cache}{profiles}{thumbnails} = {
        backend => "large_things",
    };

And then get a cache object like this:

    $c->cache("thumbnails");

It is the same as if you had done:

    $c->cache( backend => "large_things" );

=back

=head2 Misc Configuration

=over 4

=item default_store

When you do not specify a C<store> parameter in the backend configuration this
one will be used instead. This configuration parameter is not necessary if only
one store plugin is loaded.

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

=item meta data

"extra" information about the item being stored, which can be used to locate an
appropriate backend.

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


