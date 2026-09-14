def closed_default(x = <<~TEXT); end
  #{ @ }
TEXT
def endless_default(x = <<~TEXT) = x
  #{ @ }
TEXT
def multiline_default(x = <<~TEXT)
  #{ @ }
TEXT
end
def body_only(x) = <<~TEXT
  #{ @ }
TEXT
def valid_default_bad_body(x = <<~DEFAULT) = <<~BODY
  default
DEFAULT
  #{ @ }
BODY
def bad_default_valid_body(x = <<~DEFAULT) = <<~BODY
  #{ @ }
DEFAULT
  body
BODY
def second_default(x = <<~FIRST, y = <<~SECOND); end
  first
FIRST
  #{ @ }
SECOND
