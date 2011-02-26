package Code::Class::C;

use 5.010000;
use strict;
use warnings;
use Parse::RecDescent;
#use Data::Dumper;

our $VERSION = '0.02';

my $LastClassID = 0;

sub new
{
	my ($class, @args) = @_;
	my $self = bless {}, $class;
	return $self->init();
}

sub init
{
	my ($self, %opts) = @_;

	$self->{'classes'} = {},

	$::RD_ERRORS = 1;
	#$::RD_WARN = 1;
	#$::RD_HINT = 1;		
	#$::RD_TRACE = 1;
	$::RD_AUTOSTUB = 1;		

	my $Grammar = q(

		<autoaction: { [@item] } >

		signature: name "(" pair(s? /,/) ")" ":" name
			{ {'name' => $item[1], 'params' => $item[3], 'returns' => $item[6] } }

			pair: name ":" name
				{ [$item[1], $item[3]] }
			
		name: /[a-zA-Z0-9\_\s\t\n]*/
			{ $item[1] }
		
	);

	$self->{'parser'} = Parse::RecDescent->new($Grammar);
	
	return $self;
}

sub class
{
	my ($self, $name, %opts) = @_;
	die "Error: cannot redefine class '$name': $!\n" 
		if exists $self->{'classes'}->{$name};
	die "Error: classname '$name' does not qualify for a valid name\n"
		unless $name =~ /^[A-Z][a-zA-Z0-9\_]*$/;
	die "Error: classname must not be 'Object'\n"
		if $name eq 'Object';
	die "Error: classname must not be longer than 256 characters\n"
		if length $name > 256;
	
	$LastClassID++;
	my $class = {
		'id'   => $LastClassID,
		'name' => $name,
		'isa'  => $opts{'isa'}  || [],
		'attr' => $opts{'attr'} || {},
		'subs' => $opts{'subs'} || {},
	};
	
	# load files
	foreach my $nm (keys %{$class->{'subs'}}) {
		$class->{'subs'}->{$nm} = $self->_load_code_from_file($class->{'subs'}->{$nm});
	}
	
	$self->{'classes'}->{$name} = $class;
}

sub readFile
{
	my ($self, $filename) = @_;
	open SRCFILE, $filename or die "Error: cannot open source file '$filename': $!\n";
	my $classname = undef;
	my $subname   = undef;
	my $buffer    = '';
	my $l = 0;
	while (<SRCFILE>) {
		next if /^\/[\/\*]/;
		if (/^\@class/) {
			my ($class, $parents) = 
				$_ =~ /^\@class[\s\t]+([^\s\t\:]+)[\s\t]*\:?[\s\t]*(.*)$/;
			my @parents = split /[\s\t]*\,[\s\t]*/, $parents;

			$self->class($class) unless exists $self->{'classes'}->{$class};
			push @{$self->{'classes'}->{$class}->{'isa'}}, @parents;
			$classname = $class;
		}
		elsif (/^\@attr/) {
			die "Error: no classname present at line $l.\n"
				unless defined $classname;

			my ($attr, $type) =
				$_ =~ /^\@attr[\s\t]+([^\s\t\:]+)[\s\t]*\:?[\s\t]*(.*)$/;

			warn "Warning: attribute definition $classname/$attr overwrites present one.\n"
				if exists $self->{'classes'}->{$classname}->{'attr'}->{$attr};
			$self->{'classes'}->{$classname}->{'attr'}->{$attr} = $type;
		}
		elsif (/^\@sub/) {
			die "Error: no classname present at line $l.\n"
				unless defined $classname;
			
			my ($sign) = $_ =~ /^\@sub[\s\t]+(.+)[\s\t\n\r]*$/;

			warn "Warning: method definition $classname/$sign overwrites present one.\n"
				if exists $self->{'classes'}->{$classname}->{'subs'}->{$sign};
			$self->{'classes'}->{$classname}->{'subs'}->{$sign} = '';
			
			$subname = $sign;
		}
		elsif (defined $classname && defined $subname) {
			$self->{'classes'}->{$classname}->{'subs'}->{$subname} .= $_;
		}
		$l++;
	}
	close SRCFILE;
	#print Dumper($self->{'classes'});
	#exit;
	return 1;
}

sub generate
{
	my ($self, %opts) = @_;
	
	my $file     = $opts{'file'}    || 'out.c';
	my $headers  = $opts{'headers'} || [];
	my $maincode = $self->_load_code_from_file($opts{'main'} || '');
	my $topcode    = $self->_load_code_from_file($opts{'top'} || '');
	my $bottomcode = $self->_load_code_from_file($opts{'bottom'} || '');
	
	$self->_verify_members();
	
	# add standard headers needed
	foreach my $h (qw(string stdio stdlib)) {
		push @{$headers}, $h
			unless scalar grep { $_ eq $h } @{$headers};
	}

	##############################################################################	
	my $ccode = '';
	
	# write headers
	foreach my $hname (@{$headers}) {
		$ccode .= '#include ';
		if ($hname =~ /^(std|string)/) {
			$ccode .= '<'.$hname.'.h>';
		} else {
			$ccode .= '"'.$hname.'.h"';
		}
		$ccode .= "\n";
	}

	$ccode .= q{
/*----------------------------------------------------------------------------*/

typedef struct S_Object* Object;

struct S_Object {
	int classid;
	char classname[256];
	void* data;
};

/*----------------------------------------------------------------------------*/
/* String functions */

void setstr (char* dest, const char* src) {
	int i;
	for (i = 0; i < 256; i++) {
		dest[i] = src[i];
	}
}

int eq (char* s1, char* s2) {
	return (strcmp(s1, s2) == 0);
}

};

	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* Types */\n\n";
	$ccode .= '/*------------ Defines ------------*/'."\n\n";
	my $typedefs = '';
	my $structs  = '';
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		
		$ccode .= '#define '.uc($classname).'_ATTRIBUTES '."\\\n";
		#$ccode .= '  int classid'."; \\\n";
		#$ccode .= '  char classname[256]'."; \\\n"
		#	unless scalar @{$class->{'isa'}};
		$ccode .= '  int dummy'."; \\\n"
			unless scalar @{$class->{'isa'}};
		foreach my $attrname (keys %{$class->{'attr'}}) {
			my $attrtype = $class->{'attr'}->{$attrname};
			$ccode .= '  '.(exists $self->{'classes'}->{$attrtype} ? 'Object' : $attrtype).
				' '.$attrname."; \\\n";
		}
		$ccode .= "\n";

		$ccode .= '#define '.uc($classname).'_INIT(type,obj) '."\\\n";
		#$ccode .= '  (('.$classname.')obj)->classid = '.$class->{'id'}."; \\\n";
		#$ccode .= '  setstr((('.$classname.')obj)->classname, "'.$classname.'")'."; \\\n";
		foreach my $attrname (keys %{$class->{'attr'}}) {
			$ccode .= '  ((type)((obj)->data))->'.$attrname.' = 0'."; \\\n";
		}
		$ccode .= "\n";

		$typedefs .= 'typedef struct S_'.$classname.'* '.$classname.';'."\n\n";
		$structs .= 'struct S_'.$classname.' {'."\n";
		foreach my $parentclassname ($self->_get_parent_classes($classname)) {
			$structs .= '  '.uc($parentclassname).'_ATTRIBUTES'."\n";
		}
		$structs .= '  '.uc($classname).'_ATTRIBUTES'."\n";
		$structs .= "};\n\n";
	}
	$ccode .= '/*------------ Typedefs & Structs ------------*/'."\n\n";
	$ccode .= $typedefs;
	$ccode .= $structs;

	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* User top code */\n\n";
	$ccode .= $topcode."\n\n";

	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* Construction functions */\n\n";
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		$ccode .= 'Object new_'.$classname.' () {'."\n";
		$ccode .= '  Object obj = (Object)malloc(sizeof(struct S_Object));'."\n";
		$ccode .= '  obj->classid = '.$class->{'id'}.';'."\n";
		$ccode .= '  setstr(obj->classname, "'.$classname.'");'."\n";
		$ccode .= '  obj->data = malloc(sizeof(struct S_'.$classname.'));'."\n";
		$ccode .= '  obj->data = malloc(sizeof(struct S_'.$classname.'));'."\n";
		foreach my $parentclassname ($self->_get_parent_classes($classname)) {
			$ccode .= '  '.uc($parentclassname).'_INIT('.$classname.',obj)'."\n";
		}
		$ccode .= '  '.uc($classname).'_INIT('.$classname.',obj)'."\n";
		$ccode .= '  return obj;'."\n";
		$ccode .= '}'."\n\n";
	}

	##############################################################################
	my $attribs = $self->_get_unique_member_names('attr');
	my $getters = '';
	my $setters = '';
	foreach my $attrname (sort keys %{$attribs}) {
		my $attrtype = $attribs->{$attrname};
		
		$getters .= 
			(exists $self->{'classes'}->{$attrtype} ? 'Object' : $attrtype).
			' get'.ucfirst($attrname).' (Object obj) {'."\n";
		$setters .= 'void set'.ucfirst($attrname).' (Object obj, '.
			(exists $self->{'classes'}->{$attrtype} ? 'Object' : $attrtype).' value) {'."\n";
		$getters .= '  switch (obj->classid) {'."\n";
		$setters .= '  switch (obj->classid) {'."\n";
		foreach my $classname ($self->_get_classnames_with_member('attr',$attrname)) {
			my $class = $self->{'classes'}->{$classname};
			$getters .=
				'    case ('.$class->{'id'}.'):'."\n".
				($attrname eq 'classname' ?
					'      return obj->classname;'."\n" :
					'      return (('.$classname.')(obj->data))->'.$attrname.';'."\n");
			$setters .=
				'    case ('.$class->{'id'}.'):'."\n".
				($attrname eq 'classname' ?
					'      setstr(obj->classname, value);'."\n" :
					'      (('.$classname.')(obj->data))->'.$attrname.' = value;'."\n").
				'      break;'."\n";
		}
		$getters .= 	
			'    default:'."\n".
			'      printf("Cannot apply method \'get'.ucfirst($attrname).'\' to instance of class \'%s\'\n", obj->classname);'."\n".
			'      return 0;'."\n".
			'  }'."\n".
			"}\n\n";
		$setters .= 	
			'    default:'."\n".
			'      printf("Cannot apply method \'set'.ucfirst($attrname).'\' to instance of class \'%s\'\n", obj->classname);'."\n".
			'  }'."\n".
			"}\n\n";
	}
	
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* Getter functions */\n\n";
	$ccode .= $getters;

	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* Setter functions */\n\n";
	$ccode .= $setters;

	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* Functions (aka methods) */\n\n";

	# Ziel: zu jeder Funktion+Klasse rausfinden, von welcher Klasse
	#       diese Funktion tatsaechlich implementiert wird!
	my %impls = (); # '<implementing-classname>/<methodsign>' => ['<using-class1>',...]
	my %meths = (); # '<methsign>' => { '<implementing-classname>' => ['<using-class1>',...], ... }
	foreach my $methname (sort keys %{$self->_get_unique_member_names('subs')}) {
		foreach my $classname ($self->_get_classnames_with_member('subs',$methname)) {
			# find out which class implements the method for current class
			my $implementing_class = 
				$self->_get_implementing_class('subs', $classname, $methname);

			#print "method $classname/$methname impl. by $implementing_class\n";			
			
			$impls{$implementing_class.'/'.$methname} = []
				unless exists $impls{$implementing_class.'/'.$methname};
			push @{$impls{$implementing_class.'/'.$methname}}, $classname;
			
			$meths{$methname} = {} unless exists $meths{$methname};
			$meths{$methname}->{$implementing_class} = []
				unless exists $meths{$methname}->{$implementing_class};
			push @{$meths{$methname}->{$implementing_class}}, $classname;
		}
	}
	# Ziele:
	#   - jede Funktions-Implementation bekommt eine eigene C-Funktion
	#   - eine allg. Funktion, die entspr. der Klasse von self die
	#     passende Implementations-Funktion aufruft!
	my $implfuncs = '';
	my $implsigns = '';
	my $commonfuncs = '';
	foreach my $methsign (keys %meths) {
		my $sign = $self->{'parser'}->signature($methsign);
		my $returns = 
			(exists $self->{'classes'}->{$sign->{'returns'}} ? 
				'Object' : $sign->{'returns'});

		$commonfuncs .= 
			$returns.' '.$sign->{'name'}.' (Object obj'.
				$self->_get_signature_ccode($sign,0).') {'."\n".
			'  switch (obj->classid) {'."\n";

		#my @provided_classes = @{$impls{$impl}};
		#my ($implementing_class, $methsign) = split /\//, $impl;

		# specific implementation of method
		foreach my $implementing_class (keys %{$meths{$methsign}}) {
			
			$implsigns .=
				$returns.' '.$implementing_class.'_'.$sign->{'name'}.
				' (Object self'.
				     $self->_get_signature_ccode($sign,0).');'."\n";
			
			$implfuncs .=
				$returns.' '.$implementing_class.'_'.$sign->{'name'}.
				' (Object self'.
					$self->_get_signature_ccode($sign,0).') {'."\n".
				$self->{'classes'}->{$implementing_class}->{'subs'}->{$methsign}."\n".
				'}'."\n";
			
			foreach my $using_class (@{$meths{$methsign}->{$implementing_class}}) {
				$commonfuncs .=
					'    case ('.$self->{'classes'}->{$using_class}->{'id'}.'):'."\n".
					'  	  '.($sign->{'returns'} eq 'void' ? '' : 'return ').$implementing_class.'_'.$sign->{'name'}.
						'(obj'.$self->_get_signature_ccode($sign,1).');'."\n".
					($sign->{'returns'} eq 'void' ? '      break;'."\n" : '');
			}
		}
		$commonfuncs .=
			'    default:'."\n".
			'	    printf("Cannot apply method \''.$sign->{'name'}.'\' to instance of class \'%s\'\n", obj->classname);'."\n".
			($sign->{'returns'} eq 'void' ? '' : '	    return ('.$returns.')0;'."\n").
			'  }'."\n".
			'}'."\n\n";
	}
	$ccode .= $implsigns."\n".$commonfuncs.$implfuncs;
	
	#print Dumper(\%meths);
	
	#   <Anm.: jede C-Funktion bekommt als 1.Parameter immer eine Variable
	#          des Klassen-Typs namens "self">
	#
	#   <Anm.: wenn eine C-Funktion zusaetzliche Parameter hat, die
	#          Klassen-Typen haben, so werden diese in "Object" umgewandelt!>
		
	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* Destructor */\n\n";
	
	$ccode .= 'void delete (Object obj) {'."\n";
	$ccode .= '  switch (obj->classid) {'."\n";
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		$ccode .=
			'    case ('.$class->{'id'}.'):'."\n".
			'      free(('.$classname.')(obj->data));'."\n".
			'      break;'."\n";
	}
	$ccode .= '  }'."\n";
	$ccode .= '  free(obj);'."\n";
	$ccode .= "}\n\n";
	
	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* User bottom code */\n\n";
	$ccode .= $bottomcode."\n\n";

	##############################################################################
	$ccode .= "/*-----------------------------------------------------------*/\n";
	$ccode .= "/* Main function */\n\n";
	$ccode .= 'int main (int argc, char** argv) {'."\n";
	$ccode .= $maincode;
	$ccode .= "}\n";

	#exit;
	#print $ccode;

	open OUTFILE, '>'.$file 
		or die "Error: failed to open output file '$file': $!\n";
	print OUTFILE $ccode;
	close OUTFILE;	
}

sub _load_code_from_file
{
	my ($self, $code) = @_;
	if (($code =~ /^\.?\.?\//) || ($code !~ /\n/ && -f $code && -r $code)) {
		open SRCFILE, $code or die "Error: cannot open source file '$code': $!\n";
		$code = join '', <SRCFILE>;
		close SRCFILE;
	}
	return $code;
}

sub _get_signature_ccode
{
	my ($self, $sign, $callcode) = @_;
	$callcode = 0 unless defined $callcode;
	my @params = ();
	foreach my $param (@{$sign->{'params'}}) {
		my ($name, $type) = @{$param};
		$type = 'Object' if exists $self->{'classes'}->{$type};
		push @params, ($callcode ? '' : $type.' ').$name;
	}
	return (scalar @params ? ', ' : '').join(', ', @params);
}

sub _get_implementing_class
{
	my ($self, $membertype, $classname, $membername) = @_;
	my $class = $self->{'classes'}->{$classname};
	return $classname if exists $class->{$membertype}->{$membername};
	if (scalar @{$class->{'isa'}}) {
		# check if parent class implements this member
		foreach my $parentclassname (@{$class->{'isa'}}) {
			my $x = $self->_get_implementing_class(
										$membertype, $parentclassname, $membername);
			return $x if defined $x;
		}		
	}
	return undef;
}

sub _get_classnames_with_member
{
	my ($self, $membertype, $attrname) = @_;
	return (keys %{$self->{'classes'}}) if $attrname eq 'classname';
	my @classnames = ();
	foreach my $classname (keys %{$self->{'classes'}}) {
		push @classnames, $classname
			if $self->_member_is_inherited_by_class(
						$membertype, $classname, $attrname);
	}
	return @classnames;
}

sub _member_is_inherited_by_class
{
	my ($self, $membertype, $classname, $attrname) = @_;
	my $class = $self->{'classes'}->{$classname};
	return 1 if exists $class->{$membertype}->{$attrname};
	if (scalar @{$class->{'isa'}}) {
		# check if parent class have this attribute
		foreach my $parentclassname (@{$class->{'isa'}}) {
			return 1
				if $self->_member_is_inherited_by_class(
							$membertype, $parentclassname, $attrname);
		}
	}
	return 0;
}

sub _get_unique_member_names
{
	my ($self, $membertype) = @_;
	my %members = ($membertype eq 'attr' ? ('classname' => 'char*') : ());
	foreach my $classname (keys %{$self->{'classes'}}) {
		foreach my $attrname (keys %{$self->{'classes'}->{$classname}->{$membertype}}) {
			$members{$attrname} =
				$self->{'classes'}->{$classname}->{$membertype}->{$attrname};
		}
	}
	return \%members;
}

sub _get_parent_classes
{
	my ($self, $classname) = @_;
	my @parents = ();
	my $class = $self->{'classes'}->{$classname};
	foreach my $name (@{$class->{'isa'}}) {
		push @parents, $self->_get_parent_classes($name), $name;
	}
	# delete dublicates
	my @clean = ();
	map {
		my $x = $_;
		push(@clean, $x) unless scalar(grep { $x eq $_ } @clean);
	} 
	@parents;
	
	return @clean;
}

# check if attributes/methods that overwrite parent attributes/methods 
# have the same type/signature! (this is a limitation...)
sub _verify_members
{
	my ($self) = @_;
	foreach my $classname (keys %{$self->{'classes'}}) {
		my $class = $self->{'classes'}->{$classname};
		foreach my $membertype (qw(attr subs)) {
			foreach my $membername (keys %{$class->{$membertype}}) {
				if (scalar @{$class->{'isa'}}) {
					my $member = $class->{$membertype}->{$membername};
					foreach my $parentclassname (@{$class->{'isa'}}) {
						my $parentclass = $self->{'classes'}->{$parentclassname};
						if ($membertype eq 'attr') {
							if (exists $self->{$parentclassname}->{$membertype}->{$membername}) {
								my $parentmember = 
									$self->{$parentclassname}->{$membertype}->{$membername};
								if ($parentmember ne $member) {
									die "Error: type of $classname/$membername ($member) does".
									    " not match parent declaration ($parentmember)".
									    " which is a requirement!\n";
								}
							}
						}
						elsif ($membertype eq 'subs') {
							my $sign = $self->{'parser'}->signature($membername);
							foreach my $parentmember (keys %{$parentclass->{$membertype}}) {
								my $parentsign = $self->{'parser'}->signature($parentmember);
								if ($sign->{'name'} eq $parentsign->{'name'} &&
								    $membername ne $parentmember) {
									die "Error: signature of $classname/$membername does".
									    " not match parent declaration ($parentclassname/$parentmember)".
									    " which is a requirement!\n";								
								}
							}
						}					
					}
				}
			}
		}
	}
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Code::Class::C - Perl extension for creating ANSI C code from a set
of class definitions to accomplish an object-oriented programming style.

=head1 SYNOPSIS

  use Code::Class::C;
  my $gen = Code::Class::C->new();
  
  $gen->class('Shape',
    subs => {
      'getLargest(s:Shape):Shape' => 'c/Shape.getLargest.c',
      'calcArea():float' => q{
        return 0.0;
      },
    },
  );
  
  $gen->class('Circle',
    isa => ['Shape'],
    attr => {
      'radius' => 'float',
    },
    subs => {
      'calcArea():float' => q{
        return 3.1415 * getRadius(self) * getRadius(self);
      },
    },
  );
  

=head1 DESCRIPTION

This module lets you define a set of classes (consisting of
attributes and methods) and then convert these definitions
to ANSI C code.

The "cool" thing is, that the methods are written in C and
you can use the classes in an object-oriented fashion.

=head2 Constructor

=head3 new()

  my $gen = Code::Class::C->new();
  
The constructor of Code::Class::C takes no arguments and returns
a new generator instance with the following methods.

=head2 Methods

=head3 class()

The class() method lets you define a new class:

  $gen->class('Circle',
    isa => ['Shape'],
    attr => {
      'radius' => 'float',
    },
    subs => {
      'calcArea():float' => q{
        return 3.1415 * getRadius(self) * getRadius(self);
      },
    },
  );

The class() method takes as first argument the name of the class.
The name has to start with a capitol letter and may be followed
by an arbitrary amount of letters, numbers or underscore (to be
compatible with the ANSI C standard).

The special class name I<Object> is not allowed as a classname.
A classname must not be longer than 256 characters.

After the first argument the optional parameters follow
in any order:

=head4 isa => I<Arrayref of classnames>

The C<isa> option lets you specify zero or more parent classes of the class
that is to be defined.

=head4 attr => I<Hashref of attributes>

The C<attr> option lets you define the attributes of the class that
is to be defined. 

The hash key is the name of the attribute
(starting with a small letter and followed by zero or more
letters, numbers or underscore; note: attribute names are case-insensitive).

The hash value is the C-type of the attribute.
Here you can use basic C types OR class names (because each class becomes
available as a native C type when the C code is generated).

=head4 subs => I<Hashref of methods>

The C<subs> option lets you define the methods of the class that is to
be defined.

The hash key is the signature of the method, e.g.

  calcArea(float x, MyClass y):int

The hash value is the C sourcecode of the method (s.b. for details).
The hash value can optionally be a filename. In this case, the file's
content is used as the method's body.

=head3 readFile()

readFile() takes one argument, a filename, loads this file and extracts
class, attribute and method definitions from it.

  $gen->readFile('c/Triangle.c');

Here is an example file:

  //------------------------------------------------------------------------------
  @class Triangle: Shape, Rectangle
  
  //------------------------------------------------------------------------------
  @attr prop:int
  
  //------------------------------------------------------------------------------
  // calculates the area of the triangle
  //
  @sub calcArea():float
  
  return self->width * self->height;
  
  //------------------------------------------------------------------------------
  // calculates the length of the outline of the triangle
  //
  @sub calcOutline():float
  
  return getWidth(self) * 2 + getHeight(self) * 2;

A line starting with '//' is ignored.
A line that starts with an '@' is treated as a class or
attribute definition line or as the start of a method definition.
I hope this is self-explanatory?

Such files can be saved with an ".c" extension so that you can open
them in your favourite C code editor and have fun with the highlighting.

=head3 generate()

  $gen->generate(
    file    => './main.c',
    headers => ['stdio','opengl'],
    main    => 'c/main.c',
    top     => 'c/top.c',
    bottom  => 'c/bottom.c',
  );

The generate() method generates a single ANSI C compliant source file
out of the given class definitions.

The optional parameters are:

=head4 file => I<filename>

This defines the name of the C output file.

=head4 headers => I<Arrayref of headernames>

This defines C headers that are to be included in the generated C file.

=head4 main => I<Source or filename of main function body>

This defines the body (C code) of the main function of the generated
C file. This can be either C code given as a string OR a filename
which is loaded.

=head4 top => I<Source or filename of C code>

This method adds arbitrary C code to the generated C file. The code
is added after the class structs/typedefs and before the method (function)
declarations.

=head4 bottom => I<Source or filename of C code>

This method adds arbitrary C code to the generated C file. The code
is added to the end of the file, but before the main function.

=head2 C programming style

So you have defined a bunch of classes with attributes and methods.
But how do you program the method logic in C? This module promises
to make it possible to do this in an object-oriented fashion,
so this is the section where this fashion is described.

For a more complete example, see the t/ directory in the module
dictribution.

=head3 Instanciation

Suppose you defined a class named 'Circle'. You can then create an
instance of that class like so (C code):

  Object c = new_Circle();

Important: B<All class instances in C are of the type "Object">!

=head3 Destruction

A generic C function delete() is generated which can be used to
destruct any object/instance:

  Object c = new_Circle();
  delete(c); // c now points to NULL

=head3 Attribute access

Suppose you defined a class named 'Circle' with an attribute
(could also be inherited). Then you can access this attribute
the following:

  float r;
  Object c = new_Circle();
  r = getRadius(c);
  
  setRadius(c, 42.0);

As you can see, all methods (either getter or setter or other ones)
need to get the object/instance as first parameter.
B<This "self" parameter need not be written when defining the method>,
remember to define a method, only the B<addtional> parameters
are to be written:

  calcArea(int param):float

Remember: B<Always access the instance/object attributes via the
getter or setter methods!>.

=head3 Method invocation

To invoke a method on an object/instance:

  Object c = new_Circle();
  printf("area = %f\n", calcArea(c));

The first argument of the method call is the object/instance the
method is invoked on.

=head3 Access "self" from within methods

When writing methods you need access to the object instance.
This variable is "magically" available and is named "self".
Here is an example of a method body:

  printf("radius of instance is %f\n", getRadius(self));

=head3 Default attributes

The following attributes are present in all classes:

=head4 I<char*> classname

This is the name of the class of the object/instance.
To access the classname, use accessor methods like for all
other attributes, e.g.:

  Object c = new_Circle();
  printf("c is of class %s\n", getClassname(c));
  setClassname(c, "Oval");

Beware, that, when you change the classname at runtime, methods may not be able
to determine the actual implementation of a method to be applied to an
object/instance.

=head2 LIMITATIONS

=head3 Attribute types

Attributes are not allowed to overwrite attributes of parent classes.
This is because, the type of an attribute of a parent class is not allowed 
to be changed by a child class.

This limitation is due to the way methods are invoked and, to keep
the generated ANSI C code typesafe, accessor functions for attributes
return the actual C types of the attributes.

=head3 Method signatures

If a child class overwrites the method of one of its parent classes,
the signatures must be the same, B<regarding the non-class typed parameters>.

To illustrate this, here is an example of a parent class method
signature: C<doSth(Shape s, float f):void> - the first parameter is an object
of class 'Shape', the second a native C float.

Suppose another classes tries to overwrite this method. In this case the
first parameter's type is allowed to change (to any other class type!),
but the second not, because its a native type. This will work:
C<doSth(Circle s, float f):void> but this not: C<doSth(int s, float f):void>

=head2 EXPORT

None by default.

=head1 SEE ALSO

Please send any hints on other modules trying to accomplish the same
or a similar thing. I haven't found one, yet.

=head1 AUTHOR

Tom Kirchner, E<lt>tom@tomkirchner.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Tom Kirchner

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
