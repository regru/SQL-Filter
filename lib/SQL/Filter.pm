#
#===============================================================================
#
#         FILE:  SQL/Filter.pm
#
#  DESCRIPTION:  Does SQL filters from filter building rules and input hash of data.
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Pavel Boldin (), <davinchi@cpan.org>
#      COMPANY:  
#      VERSION:  1.0
#      CREATED:  02.08.2009 03:12:46 MSD
#     REVISION:  ---
#===============================================================================

package SQL::Filter;

use strict;
use warnings;

use Data::Dumper;

#use Any::Moose;

use Clone qw/clone/;

use Data::Visitor;
use base 'Data::Visitor';

use constant DEBUG => not not our $DEBUG || $ENV{SQL_FILTER_DEBUG};
#use constant DEBUG => 1;

$Data::Dumper::Indent = 1;

sub new {
    my $class = shift;
    $class = ref $class || $class;

    my %param = @_;

    ref $param{filter} eq 'ARRAY'
	or  die "filter should be arrayref";

    ref $param{input} eq 'HASH'
	or  die "input should be hash";

    $param{field} = [ $param{field} ] unless ref $param{field};
    $param{table} = [ $param{table} ] unless ref $param{table};

    ref $param{field} eq 'ARRAY'
	or die "field should be scalar or array";

    ref $param{table} eq 'ARRAY'
	or die "table should be scalar or array";

    my $self = {
	where => [],
	%param,
    };

    bless $self, $class;

    $self->_make_filter;
    $self;
}

#===  FUNCTION  ================================================================
#         NAME:  _arrize
#      PURPOSE:  I want array from this
#===============================================================================
sub _arrize {
    ref $_[0] eq 'ARRAY' ? $_[0] : [ $_[0] ];
}


#===  FUNCTION  ================================================================
#         NAME:  _make_filter
#      PURPOSE:  Add fields necessary for making SQL query
#		 into this SQL::Filter instance for that input and filter.
#   PARAMETERS:  only $self, you can also provied $filter (from instance by default, then from get_filter instance method)
#      RETURNS:  nothing
#  DESCRIPTION:  
#		Uses recursive mechanism to ->merge instance's SQL fields
#		with fields of filter for this input.
#		Calls ->_set_input when done.
#===============================================================================
sub _make_filter {
    warn "_make_filter ". Dumper \@_ if DEBUG;

    my $self  = shift;
    my $filter = shift || $self->{filter} || eval { $self->get_filter };

    my $input  = $self->{input};

    foreach my $f ( @$filter ) {

	$self->_merge( $f );

	my $k = $f->{field};
	#warn "k = $k";
	next unless $k;

	my $v = $input->{ $k };
	#warn "v = $v";
	#my $v = $k ? $input->{ $k } : undef;

	if ( $v and my $cond  = $f->{cond} ) {
	    if ( my $condition = $cond->{ $v } ) {
		$self->_make_filter(
		    _arrize( $condition ),
		);
		next;
	    }
	}

	#next unless defined $v;

	my $fname = $v ? 'on_true' : 'on_false';

	warn "$fname ", Dumper $input if DEBUG;

	if ( my $filter = $f->{ $fname } ) {
	    #warn 'on_true/on_false ', Dumper $filter;
	    $self->_make_filter(
		_arrize( $filter ),
	    );
	}

	#$output->merge( $f->{on_true }, $input ) if  $v && $f->{on_true };
	#$output->merge( $f->{on_false}, $input ) if !$v && $f->{on_false};
    }

    $self->_set_input();

    #return $output;
}


#===  FUNCTION  ================================================================
#         NAME:  _merge
#      PURPOSE:  Merges fields required for SQL::Abstract from filter to instance
#   PARAMETERS:  fields, hashref from filter: where, tables, fields
#      RETURNS:  nothing
#===============================================================================
sub _merge {
    warn '_merge: '.Dumper \@_ if DEBUG;

    my $self   = shift;
    my $fields = shift;

    my $where = $fields->{ where };
    my $self_where = $self->{ where };

    #warn Dumper $where;

    if ( $where ) {
	# CLONE IT!
	$where = clone( $where );

	if ( ref $where eq 'HASH' ) {
	    $where = [ -nest => $where ];
	}
	elsif ( ref $where ne 'ARRAY' ) {
	    $where = [ $where ];
	}

	foreach my $field ( @$where ) {
	    if ( ref $field eq 'CODE' ) {
		$field->( $self );
		next;
	    }
	    warn Dumper $field if DEBUG;
	    push @$self_where, $field;
	}
    }

    push @{ $self->{ $_ } }, @{ $fields->{ $_.'s' } || [] } for qw/table field/;
}

#---------------------------------------------------------------------------
#  Data::Visitor subroutines
#---------------------------------------------------------------------------
sub visit_value {
    $_[1] =~ s/\$([\w_]+)/$_[0]->{input}{ $1 }/gxe if $_[1];
    if ( DEBUG && $1 ) {
	warn "Substitute $1 with ".$_[0]->{input}{ $1 };
    }
    if ( $1 && ref $_[0]->{input}{ $1 } ) {
	$_[1] = $_[0]->{input}{ $1 };
    }
    $_[1];
}

sub visit_hash_value {
    my ($self, $v, $k) = @_;

    my $input = $self->{input};

    if ( $k eq '-like' ) {
	$v =~ s/\$([\w_]+)/$input->{ $1 }/gxe;
	$_[1] = $v =~ tr/%*_?/%%__/ ? $v : q{%}.$v.q{%};

	return;
    }

    #warn "key is $k";
    return $self->SUPER::visit( $_[1] );
    #return $h unless join('', keys %$h) eq '-like';

    #warn 'visit_hash: '. Dumper @_;
    #return { -like => $v =~ tr/%*_?/%%__/ ? $v : q{%}.$v.q{%} };
}


#===  FUNCTION  ================================================================
#         NAME:  _set_input
#      PURPOSE:  Set inputs in constructed $where hashref from input of instance
#   PARAMETERS:  $self
#      RETURNS:  nothing
#  DESCRIPTION:  visits everything with our visit_* subroutines,
#		 see Data::Visitor
#===============================================================================
sub _set_input {
    my $self  = shift;

    $self->visit( $self->{ where } );
}


#===  FUNCTION  ================================================================
#         NAME:  select
#      PURPOSE:  converts SQL::Filter to SQL statement and @bind values
#      RETURNS:  ($stmt, @bind)
#===============================================================================
sub select {
    my $self = shift;
    my @rest = @_;

    warn 'select '. Dumper $self if DEBUG;

    my $n = SQL::Abstract::My->new(
	logic	      => 'and',
	limit_dialect => 'LimitXY',
    );

    if ( @rest > 1 ) {
	return $n->select( 
	    $self->{ table },
	    $self->{ field },
	    $self->{ where  },
	    @rest,
	);
    }
    else {
	return $n->SQL::Abstract::select( 
	    $self->{ table },
	    $self->{ field },
	    $self->{ where  },
	    @rest,
	);
    }
}

sub tables {
    SQL::Abstract::My->new()->_table( shift->{table} );
}

sub fields {
    join ', ', @{ shift->{ field } };
}

sub where {
    my $self = shift;

    my @rest = @_;

    my ($stmt, @bind) = 
	SQL::Abstract::My->new(
	    logic => 'and',
	    limit_dialect => 'LimitXY',
	)->where( 
	    $self->{ where },
	    @rest,
	);

    $stmt =~ s/^\s*WHERE//;

    ($stmt, @bind);
}

#---------------------------------------------------------------------------
#  SQL::Abstract::My contains my code for JOINs
#---------------------------------------------------------------------------
package # hide from PAUSE
	SQL::Abstract::My;

use SQL::Abstract::Limit;
use base 'SQL::Abstract::Limit';

sub _table  {
    my $self = shift;
    my $from = shift;
    $self->_SWITCH_refkind($from, {
	ARRAYREF     => sub {
	    my $o = join ', ', map { $self->_quote( $_ ) } grep { ref $_ ne 'ARRAY' } @$from;
	    $o .= ' ' . join ' ', map {
		if ( $_->[0] =~ /JOIN/i ) {
		    $_->[0]
		}
		else {
		    my $j = $self->_sqlcase('LEFT JOIN ') . $_->[0];     
		    @$_ == 1	? $self->_sqlcase('NATURAL ') . $j
				: $j . $self->_sqlcase(' ON ') .  $_->[1];
		}
	    } grep { ref $_ eq 'ARRAY' } @$from;
	    $o;
	},
	SCALAR       => sub {$self->_quote($from)},
	SCALARREF    => sub {$$from},
	ARRAYREFREF  => sub {join ', ', @{ $$from };},
    });
}


1;

__END__

=head1 NAME

SQL::Filter - Generate complex SQL where from Perl data structures

=head1 SYNOPSIS

    use SQL::Filter;

    my $filter = SQL::Filter->new(
	table => 'testme t',
	field => '*',
	filter => [ # or subclass and return them from get_filter method
	    {
		tables  => [ [ 'another_test a' ] ], # natural join that
		field  => 'field',
		on_true => {
		    where => {
			'a.field' => { -like => '$field' },
		    },
		},
	    },
	    {
		field => 'another_field',
		cond   => {
		    first_value => {
			where => {
			    'a.first_value' => 
				{ -not_like => 'first_value' },
			},
		    },
		},
	    },
	],
	input => {
	    field => 'value',
	    another_field => 'first_value',
	},
    );

    my ($stmt, @bind) = $filter->select;

=head1 DESCRIPTION

Making filter queries from complicated database always was pain in ass.
So, after attempting to patch such code, I decided to write this module, which
in exactly can be treated like an extension to SQL::Abstract which it uses.

Now there is no need to put a bunch of ifs and C<$sql .= '...'> statements in
your perl code. All you need to do a test is there, in that module.

Filters are build like mentoined in example from L</"SYNOPSIS"> section.

    my @filter = (
	{
	    field => 'field_name',
	    cond => {
		value1 => {
		    # hash to merge with when $input->{field_name} is == 'value1',
		},
	    },
	    on_true => {
		# hash to merge with when $input->{field_name} is true
	    },
	    on_false => {
		# hash to merge with when $input->{field_name} is false
	    },
	    # fields to merge with anyway
	    where => {
		'test' => '$field_name',
	    },
	    tables => [ [ 'table', ] ], # NATURAL LEFT JOIN with table
	    fields => [ \'(SELECT COUNT(*) FROM s WHERE s.id = this.id) AS cnt' ],
	},
	{
	    ....
	},
    );

At first mechanism merges instance L<SQL::Abstract> values with filters one.
Then any field name given in C<< ->{field} >> will be checked against 
conditions given in C<cond>, if none is found here, C<on_true> or C<on_false> 
will be used.

When condition hash is fetched (either from C<cond>, C<on_true> or C<on_false>)
code recurses into that hash, which can contain C<cond>, C<field> and C<on_true>/C<on_false> values as well and should contain at least C<where> field.

After all filters are processed, C<$self->_set_input> is called and using L<Data::Visitor> all filter values started with C<$> are replaced with corresponding C<$input> value. You can subclass and replace either C<_set_input> or C<visit_hash>/C<visit_value> to substitute values your own way (for example, substitute array).

Please, see tests for more details. More documentation is pending.

=head1 FUNCTIONS

One main function is the constructor, which gets almost all data need to
build a filter. Another function is L</"_make_filter"> which merges all the data to make the filter's SQL::Abstract data.
And final one is L</"select"> which converts SQL::Abstract to statement and bind values one can supply to ->prepare and ->execute.

=head2 new(option => 'value')

The C<new()> function takes following options

=over

=item table

Table name to generate SQL query for. Can be list of tables (arrayref).

=item field

Field (or fields) name to fetch from table. Can be array of fields or just single field.

=item filter

Filter - arrayref of described above format.

=item input

Input data for constructing filter SQL based on these data.

=head2 $self->_make_filter( [ $filter ] )

Processes input and filter and then adds SQL::Abstract data to C<$self> 
using values from C<< $self->{input} >> and filter from C<$filter>.
If C<$filter> is not given, then C<< $self->{filter} >> is used,
if even this dont helps, C<< $self->get_filter >> is called.

This function recurses heavily. Logic is described above.

=head2 $self->_merge( $fields )

Merge C<$fields> into C<$self>. Merged C<fields> (list of fields to select),
C<tables> (list of tables to select from, including join),
C<where> (hash with conditions in form of L<SQL::Abstract>).

=head2 C<< $self->_set_input() >>

Substitutes C<< $self->{input} >> values into C<< $self->{where} >> hash,
using magic of Data::Visitor. You can extend this method with arbitrary
one to, for example, substitute array values.

=head2 C<< $self->visit_value() >>
=head2 C<< $self->visit_hash_value() >>

Methods for Data::Visitor. First one replaces '$value' by
C<< $input->{value} >>, second one searches for C<-like> key and changes
it values in appropriate way. In exactly, processes LIKElity patterns.

=head2 C<< $self->select() >>

Returns SELECT statement and bind values from call of SQL::Abstract.

=head1 SEE ALSO

L<SQL::Abstract>, L<DBIx::Class>, L<Data::Visitor>.

=head1 AUTHOR

Copyright (c) 2009 Pavel Boldin <davinchi@cpan.org>. All Rights Reserved.

=head1 LICENSE

This module is free software; you may copy this under the terms of
the GNU General Public License, or the Artistic License, copies of
which should have accompanied your Perl kit.

=cut

