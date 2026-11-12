# Configuration

Set options in an initializer:

```ruby
# config/initializers/live_cable.rb
LiveCable.configure do |config|
  config.verbose_errors = false
end
```

## `verbose_errors`

Whether the error a component is replaced with shows the exception's class,
message and backtrace, or only "An error occurred". Errors are reported with
`Rails.error.report` either way.

**Default:** `true` outside production, `false` in production.

See [Error Handling](/guide/error-handling#default-behaviour).

## `structured_blocks`

Whether a control block in a `.live.erb` template (an `if`, `unless`, `case` or
loop) compiles to static markup and values, so a change inside it sends only
the values that changed. Set it to `false` to send each block as one HTML
string. Templates read it when they compile, so set it in an initializer.
[Collection streams](/guide/collection-streams) need it: with it off, a
template that renders one fails to compile.

**Default:** `true`.

See [Control Blocks](/guide/partial-rendering#control-blocks).

## `verify_stream_items`

Whether [collection streams](/guide/collection-streams) check what the compiler
can't see. With it on, rendering raises `LiveCable::Error`:

- when a row element that sets its own `id` renders something other than the
  row's key there, naming the `dom_id:` that would match it;
- when a component's template doesn't render a stream the component declares.
  Compound components aren't checked, since a variant may leave a stream out.

The checks run every row's `id` code once more, so leave them off in
production.

**Default:** `true` outside production, `false` in production. It is on in the
test environment, so `LiveCable::Testing` specs run the checks.

## Next Steps

- [Component API](/api/component)
- [View Helpers](/api/helpers)
