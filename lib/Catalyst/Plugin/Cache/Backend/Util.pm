#!/usr/bin/perl

package Catalyst::Plugin::Cache::Backend::Util;

use strict;
use warnings;

sub default_ttl {
    my ( $self, $key ) = @_;
    2 * 60 * 60; # 2 hours
}

sub expires {
    my ( $self, $key ) = @_;
    time() + $self->default_ttl( $key );
}

sub serialize_value {

}

sub deserialize_value {

}

__PACKAGE__;

__END__

=pod

=head1 NAME

Catalyst::Plugin::Cache::Backend::Util - Useful base class methods for cache
backends.

=head1 SYNOPSIS

	use Catalyst::Plugin::Cache::Backend::Util;

=head1 DESCRIPTION

=cut


