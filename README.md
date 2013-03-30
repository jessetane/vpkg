```
              __          
 .--.--.-----|  |--.-----.
 |  |  |  _  |    <|  _  |
  \___/|   __|__|__|___  |
       |__|        |_____|
	
```
A language agnostic, version oriented package manager.

## Why
Just some homework to learn shell scripting.

## How
Sourcable shell scripts.

## Install
`curl "https://raw.github.com/jessetane/vpkg/refactor/.vpkg" | bash`

## Usage
`vpkg <command> [options] <package> [<build>] [<version>]`  

Commands:  
```bash
# update registries and recipes or just a single package
vpkg update [<package>]

# attempt to lookup a package url in your registries
vpkg lookup <package>

# get source code
add <registered-package> [<package>]
    <url> [<package>]

# build a package from source and place it in lib/<package>/<build>
build <package> [<build>] [<version>]
      <url> [<package>] [<build>] [<version>]

# destroy a lib/<package>/<build>
destroy <package> [<build>]

# gets the source, generates a build, and links it
install <package> [<build>] [<version>]
        <url> [<package>] [<build>] [<version>]

# unlink <package>
uninstall <package> [<build>]

# ensure a specific <package>/<build> has priority in your PATH
load <package> [<build>]

# ..
unload <package>
```

## Dependencies
* bash  
* cat  
* curl  
* mktemp  
* readlink  
* argue  

## License
[WTFPL](http://www.wtfpl.net/txt/copying/)
