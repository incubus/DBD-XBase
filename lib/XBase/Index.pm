
=head1 NAME

XBase::Index - base class for the index files for dbf

=head1 SYNOPSIS

No synopsis yet, sorry.

=head1 DESCRIPTION

=head2 Proposal:

Possible methods for the index package:

=over 4

=item find($key)

Return the list of record numbers of records that exactly match the $key.

=item find3($key)

Return three array references, containg lists of record numbers of
records lower, equal and higher (respectivelly) compared to the $key.

=item find_with_recno($key, $recno)

Returns the object(?) or some identifier of the row in the B-tree
matching the $key and pointing to the $recno. This should be usefull
for updates where we need to rewrite the content of the index.

=back

=cut

package XBase::Index::Page;



1;

