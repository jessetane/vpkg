```
              __          
 .--.--.-----|  |--.-----.
 |  |  |  _  |    <|  _  |
  \___/|   __|__|__|___  |
       |__|        |_____|
	
```
A language agnostic, version oriented package manager.

## Why
Started out as a project to learn bash scripting...

## How
Sourcable shell scripts.

## Install
`curl "https://raw.github.com/jessetane/vpkg/refactor/.vpkg" | bash`

## Usage
`vpkg <command> [options] [arguements]`
Commands:
* `update [<package>]`
* `lookup <package>`
* `add <remote-package> [<package>]  
    <url> [<package>]`
* `rm <package>`
* `build <package> [<build>] [<version>]  
      <url> [<package>] [<build>] [<version>]`
* `destroy <package> [<build>]`
* `install <package> [<build>] [<version>]  
        <url> [<package>] [<build>] [<version>] `
* `uninstall <package> [<build>]`
* `load <package> [<build>]`
* `unload <package>`
```

## Dependencies
bash  
mktemp  
cat  
curl  
argue  

## License
[WTFPL](http://www.wtfpl.net/txt/copying/)
