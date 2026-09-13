def deliver(payload, count = pair(1, 2), *rest, required:, timeout: {seconds: 2}, **options, &block)
  payload
end
def bare value, optional = [1, 2], key:, flag: true; end
def anonymous(*, **, &); end
def empty; end
def parenthesized(); end
def setter=(value); end
def forwarded(head, ...); target(head, ...); end
def reject_keywords(**nil); end
def destructured((left, right)); end
def defaults(callback = ->(left, right) { [left, right] }, text = "a,b", pattern = /a,b/); end
