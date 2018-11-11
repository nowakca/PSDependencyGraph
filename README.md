# PSDependencyGraph

Have you inherited some powershell code with a bunch of functions but you don't know where to get started? This can help.

Kick off `show-PSScriptCallGraph` to get a sense of what is calling what and you'll have a good idea where to start in trying to understand that code.

This is NOT a polished product, I got it working enough to get what I needed out of it at the moment, but it should be easily expandable to wider use cases.

## Powershell compatibility

This has only been tested on Powershell Core 6.1 so far, but there's no reason it shouldn't work on any reasonably recent version of Powershell.

## Usage

`Import-Module PSDependencyGraph` to get things loaded.

Example usage:

    show-PSScriptCallGraph sampleScript.ps1

Or of you want to see the dependencies within this module as a PDF File (Warning: not very interesting):

    get-ChildItem (get-module PSDependencyGraph).ModuleBase -Recurse -Filter *.ps1 | show-PSScriptCallGraph -OutputFormat pdf

Refer to `get-help show-PSScriptCallGraph` for more details

## Scope

This currently only parses the given Powershell scripts for function definitions and commands. It does understand functions nested in other functions, but it doesn't understand dynamically generated functions nor does it know what to do with modules or variables.

## Dependencies

### PSGraph (only required for the graph portion)

If you want a graph to be exported, you'll need to install [PSGraph](https://github.com/KevinMarquette/PSGraph/tree/master/PSGraph/Public).

Kevin Marquette has nicely published it in the Powershell Gallery, so a simple `install-module PSGraph` should do the trick.  (It did for me on Powershell Core at least)

### graphviz (only required if you're using PSGraph)

You can refer to [PSGraph](https://github.com/KevinMarquette/PSGraph/tree/master/PSGraph/Public) for informatino about installing graphviz.

If you're running powerhsell core on MacOS, a simple `brew install graphviz` was enough to get it going (since I had HomeBrew installed already).