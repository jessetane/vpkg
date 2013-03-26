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
Sourcable shell script.

## Install
`curl "https://raw.github.com/jessetane/vpkg/refactor/.vpkg" | bash`

## Usage
* braces indicate an [<argument>] is optional
vpkg get https://github.com/jessetane/httpcat.git [<name>]      # acquire teh source code
     build <package> <build> [<version>]                        # create a build
     install <package> <build>                                  # links files into PKG_HOME/bin
     uninstall <package> [<build>]                              # ..
     load <package> [<build>]                                   # updates your PATH
     unload httpcat                                             # ..
```

## Dependencies
bash  
mktemp  
cat  
curl  
argue  

## License
[WTFPL](http://www.wtfpl.net/txt/copying/)
