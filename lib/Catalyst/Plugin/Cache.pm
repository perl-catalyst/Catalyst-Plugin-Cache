#!/usr/bin/perl

package Catalyst::Plugin::Cache;
use base qw/Class::Data::Inheritable Class::Accessor::Fast/;

use strict;
use warnings;

use Scalar::Util ();
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

# don't die even if we don't have cache backends
sub setup_cache_backends { shift->NEXT::setup_cache_backends(@_) }

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

sub curry_cache {
    my ( $c, @meta ) = @_;
    return Catalyst::Plugin::Cache::Curried->new( $c, @meta );
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

# this gets a shit name so that the plugins can override a good name
sub choose_cache_backend_wrapper {
    my ( $c, @meta ) = @_;

    Carp::croak("meta data must be an even sized list") unless @meta % 2 == 0;

    my %meta = @meta;
    
    # allow the cache client to specify who it wants to cache with (but loeave room for a hook)
    if ( exists $meta{backend} ) {
        if ( Scalar::Util::blessed($meta{backend}) ) {
            return $meta{backend};
        } else {
            return $c->get_cache_backend( $meta{backend} ) || $c->default_cache_backend;
        }
    };
    

    $meta{caller} = [ caller(2) ] unless exists $meta{caller}; # might be interesting

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

	use Catalyst::Plugin::Cache;

=head1 DESCRIPTION

=cut


