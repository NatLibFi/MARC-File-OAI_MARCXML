package MARC::File::OAI_MARCXML;

=head1 NAME

MARC::File::OAI_MARCXML - OAI_MARCXML-specific file handling

=cut

our $VERSION = '1.1';
our $USE_UTF8 = 1;

use strict;
use integer;

use XML::DOM;
use XML::Writer;
use vars qw( $ERROR );
use MARC::File::Encode qw( marc_to_utf8 );

use MARC::File;
use vars qw( @ISA ); @ISA = qw( MARC::File );

use MARC::Record qw( LEADER_LEN );
use MARC::Field;
use constant SUBFIELD_INDICATOR     => "\x1F";
use constant END_OF_FIELD           => "\x1E";
use constant END_OF_RECORD          => "\x1D";
use constant DIRECTORY_ENTRY_LEN    => 12;

=head1 SYNOPSIS

    use MARC::File::OAI_MARCXML;

    my $file = MARC::File::OAI_MARCXML->in( $filename );

    while ( my $marc = $file->next() ) {
        # Do something
    }
    $file->close();
    undef $file;

=head1 EXPORT

None.

=head1 METHODS

=cut

sub _next {
    my $self = shift;
    my $fh = $self->{fh};

    my $reclen;
    return if eof($fh);

    local $/ = END_OF_RECORD;
    my $OAI_MARCXML = <$fh>;

    # remove illegal garbage that sometimes occurs between records
    $OAI_MARCXML =~ s/^[ \x00\x0a\x0d\x1a]+//;

    return $OAI_MARCXML;
}

=head2 decode( $string [, \&filter_func ] )

Constructor for handling data from a OAI_MARCXML file.  This function takes care of
all the tag directory parsing & mangling.

Any warnings or coercions can be checked in the C<warnings()> function.

The C<$filter_func> is an optional reference to a user-supplied function
that determines on a tag-by-tag basis if you want the tag passed to it
to be put into the MARC record.  The function is passed the tag number
and the raw tag data, and must return a boolean.  The return of a true
value tells MARC::File::OAI_MARCXML::decode that the tag should get put into
the resulting MARC record.

For example, if you only want title and subject tags in your MARC record,
try this:

    sub filter {
        my ($tagno,$tagdata) = @_;

        return ($tagno == 245) || ($tagno >= 600 && $tagno <= 699);
    }

    my $marc = MARC::File::OAI_MARCXML->decode( $string, \&filter );

Why would you want to do such a thing?  The big reason is that creating
fields is processor-intensive, and if your program is doing read-only
data analysis and needs to be as fast as possible, you can save time by
not creating fields that you'll be ignoring anyway.

Another possible use is if you're only interested in printing certain
tags from the record, then you can filter them when you read from disc
and not have to delete unwanted tags yourself.

=cut

sub decode {

    my $text;
    my $location = '';

    ## decode can be called in a variety of ways
    ## $object->decode( $string )
    ## MARC::File::OAI_MARCXML->decode( $string )
    ## MARC::File::OAI_MARCXML::decode( $string )
    ## this bit of code covers all three

    my $self = shift;
    if ( ref($self) =~ /^MARC::File/ ) {
        $location = 'in record '.$self->{recnum};
        $text = shift;
    } else {
        $location = 'in record 1';
        $text = $self=~/MARC::File/ ? shift : $self;
    }
    my $filter_func = shift;

	my $parser = new XML::DOM::Parser;
	
	my $doc = undef;
	eval { $doc = $parser->parse($text) };
	if ($@)
	{
		die("could not parse xml: $!");
		
	}

    # create an empty record which will be filled.
    my $marc = MARC::Record->new();

  my @controlfields = $doc->getElementsByTagName('fixfield');
  foreach my $controlfield (@controlfields)
  {
    my $tag = $controlfield->getAttributeNode('id')->getValue();

    my $fielddata = get_xml_text($controlfield);
    $fielddata =~ s/\r\n/ /g;
    $fielddata =~ s/\r//g;
    $fielddata =~ s/\n/ /g;
    
   
    if ($tag eq "LDR") {
        $marc->leader($fielddata);
    } else {
        my $field = MARC::Field->new($tag, $fielddata);
        $marc->append_fields($field);
    }
 
  }
  
  my @datafields = $doc->getElementsByTagName('varfield');
  foreach my $datafield (@datafields)
  {
    my $tag = $datafield->getAttributeNode('id')->getValue();

    my $ind1 = $datafield->getAttributeNode('i1')->getValue();
    my $ind2 = $datafield->getAttributeNode('i2')->getValue();
	
	my $field;

    my @subfields = $datafield->getElementsByTagName('subfield');
    foreach my $subfield (@subfields)
    {
      my $sub_code = $subfield->getAttributeNode('label')->getValue();
      my $sub_contents = get_xml_text($subfield);
      $sub_contents =~ s/\r\n/ /g;
      $sub_contents =~ s/\r//g;
      $sub_contents =~ s/\n/ /g;

		if (!defined($field)) {
			$field = MARC::Field->new($tag, $ind1, $ind2,$sub_code => $sub_contents );
		} else {
			$field->add_subfields($sub_code => $sub_contents);
		}
    }

   $marc->append_fields($field);

	
  }
  $doc->dispose();
  

  return $marc;
}

sub get_xml_text($)
{
  my ($node) = @_;

  return '' if (!$node);

  $node = $node->getFirstChild();
  return '' if (!$node);

  my $str = $node->getData();

  return $USE_UTF8 ? $str : return pack('C*', unpack('U0C*', $str));
}



=head2 encode()

Returns a string of characters suitable for writing out to a OAI_MARCXML file

=cut

sub encode() {
    my ($doc, $writer);
    my $marc = shift;
    $marc = shift if (ref($marc)||$marc) =~ /^MARC::File/;

    if ($USE_UTF8) {
	$writer = new XML::Writer(OUTPUT => \$doc, ENCODING => 'utf-8', DATA_INDENT => 2);
	$writer->xmlDecl("UTF-8");
    } else {
	$writer = new XML::Writer(OUTPUT => \$doc);
    }

    $writer->startTag("record");
    $writer->startTag("oai_marc");
    
    $writer->startTag("fixfield", "id" => "LDR");
    $writer->characters($marc->leader());
    $writer->endTag("fixfield");
  
	for my $field ($marc->fields()) {
		
		if ($field->is_control_field()) {
			
			$writer->startTag("fixfield", "id" => $field->tag());
			
			$writer->characters($field->data());
			
			$writer->endTag("fixfield");
			
		} else {
			
			$writer->startTag("varfield", "id" => $field->tag(), "i1"=>$field->indicator(1), "i2"=>$field->indicator(2));
			
			for my $subfield ($field->subfields) {
				
	
				$writer->startTag("subfield", "label" => $subfield->[0]);
				$writer->characters($subfield->[1]);
				$writer->endTag("subfield");
			
			}
			
			
			$writer->endTag("varfield");
		}
		
		
	}
	
	$writer->endTag("oai_marc");
    $writer->endTag("record");
	$writer->end();
 
	return $doc;

}
1;

__END__

=head1 RELATED MODULES

L<MARC::Record>

=head1 TODO

filter func is not implemented in decode.

=head1 LICENSE

This code may be distributed under the same terms as Perl itself.

Please note that these modules are not products of or supported by the
employers of the various contributors to the code.

=head1 AUTHOR

Pasi Tuominen, C<< <pasi.e.tuominen@helsinki.fi> >>

=cut

