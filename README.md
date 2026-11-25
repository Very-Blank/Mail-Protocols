
## Inbox protocol

All codes, lengths and commands shall be written as bytes backed by 32 bit little endian unsigned integer.
Altough commands do have an ascii reposentation they should be treated as numbers.
Lengths specify the amount of bytes the server will be reading from you next or vice versa.

## Post

Command `1414745936`, which is `POST` in ascii.

- Connect
- Read `<code>` (`OK`)
- Write `<command><length>`
- Read `<code>`, (`OK`, `TMD`)
  On code (`TMD`) error happened and you must exit.
- Write `<json>`
- Read `<code><length>` (`OK`, `NSU`)
  On code (`NSU`) error happened, length will be (0) and you must exit.
- Read `<json>`
- exit

## Read

Command: `1145128274`, which is `READ` in ascii.

- Connect
- Read `<code>` (`OK`)
- Write `<command><length>`
- Read `<code>`, (`OK`, `TMD`)
  On code (`TMD`) error happened and you must exit.
- Write `<json>`
- Read `<code><length>` (`OK`, `NSU`)
  On code (`NSU`) error happened, length will be (0) and you must exit.
- Read `<json>`
- exit

### Reply codes

Ok (0), Okay response.
ERR (1), Too much data.
TMD (2), Too much data.
NSU (3), No such user.
