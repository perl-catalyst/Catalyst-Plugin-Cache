#!/usr/bin/perl

package Catalyst::Plugin::Cache::Curried;

use strict;
use warnings;

use base qw/Class::Accessor::Fast/;

use Scalar::Util ();

__PACKAGE__->mk_accessors(qw/c meta/);

sub new {
    my ( $class, $c, @meta ) = @_;

    my $self = $class->SUPER::new({
        c    => $c,
        meta => \@meta,
    });

    Scalar::Util::weaken( $self->{c} );

    return $self;
}

sub backend {
    my ( $self, $key ) = @_;
    $self->c->choose_cache_backend( @{ $self->meta }, key => $key )
}

sub set {
    my ( $self, $key, $value ) = @_;
    $self->c->cache_set( $key, $value, @{ $self->meta } );
}

sub get {
    my ( $self, $key ) = @_;
    $self->c->cache_get( $key, @{ $self->meta } );
}

sub remove {
    my ( $self, $key ) = @_;
    $self->c->cache_remove( $key, @{ $self->meta } );
}

__PACKAGE__;

__END__

=pod

=head1 NAME

Catalyst::Plugin::Cache::Curried - Curried versions of C<cache_set>,
C<cache_get> and C<cache_remove> that look more like a backend.

=head1 SYNOPSIS

	sub begin : Private {

    }

=head1 DESCRIPTION

=cut


