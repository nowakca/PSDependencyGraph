function build-PSScriptCallGraph {
    <#
    .DESCRIPTION
    Given a set of Powershell source files, emit a list of which functions call which other functions, and optionally generate and/or show a graph illustrating those dependencies.

    To generate a graph, specify a -OutputFormat (png is a reasonable one if you're not sure what to choose)
    
    .EXAMPLE
    get-childitem *.ps1 | build-PSScriptCallGraph

    Read all the .ps1 files from the current directory and present a list of functions in them, along with which functions they called that were among the given files.

    .EXAMPLE
    build-PSScriptCallGraph -psFilePath "myFile.ps1" -dontRestrainGraphToProvidedFunctions

    Read all the .ps1 files from the current directory and present a list of functions in them, along with which functions they called, regardless of where they come from.

    .EXAMPLE
    Get-ChildItem *.ps1 | build-PSScriptCallGraph -OutputFormat png

    Read all the .ps1 files from the current directory and present a list of functions in them, generate a png formatted graph, and then launch it.

    .EXAMPLE
    Get-ChildItem *.ps1 | build-PSScriptCallGraph -OutputFormat png -HideGraph

    Read all the .ps1 files from the current directory and present a list of functions in them, generate a png formatted graph, but don't launch it.

    .NOTES
    The optional graphing portion relies on PSGraph, by Kevin Marquette
    https://github.com/KevinMarquette/PSGraph

    This has only been tested on Powershell Core 6.1, but it should work in most modern Powershell verisons.
    #>
    [CmdletBinding()]
    Param(
        # Path to powershell script file(s) to be analyzed
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $psFilePath,

        # Specify this in order to allow the graph to include all commands instead of restricting it to just what's defined in the specified files.
        [SWITCH]
        $dontRestrainGraphToProvidedFunctions,


        #The destination for the generated file. (If unspecified will default to sample.<outputformat>
        [string]
        $DestinationPath,

        # The file type used when generating an image
        [ValidateSet('jpg', 'png', 'gif', 'imap', 'cmapx', 'jp2', 'json', 'pdf', 'plain', 'dot', 'svg')]
        [string]
        $OutputFormat,

        # The layout engine used to generate the image
        [ValidateSet(
            'Hierarchical',
            'SpringModelSmall' ,
            'SpringModelMedium',
            'SpringModelLarge',
            'Radial',
            'Circular',
            'dot',
            'neato',
            'fdp',
            'sfdp',
            'twopi',
            'circo'
        )]
        [string]
        $LayoutEngine = "Hierarchical",

        # PreventIf an Outputformat is specified, prevent the generated file from being launched automatically
        [switch]
        $HideGraph
    )



    Begin {
        $tokens = New-Object Collections.ArrayList

        # Implementing a mini FSM so I can expand this to get fancier later easily
        enum mState {
            init = 0
            functionSeen = 1
            functionNamed = 2
        }

        # Record the order we detected function in
        $funcOrder = @()

        # Given a key of a function name, return what other functions it's called
        # The value will be a hashtable as well, whose key is the called function name, and value is $true
        # This is just to make deduplication fast and easy
        $called = @{}
    } # Begin Block



    Process {
        $parseErrors = @() # Need something to store the errors in, even if I don't do anything with them

        write-verbose "Reading/Parsing file $psFilePath"
        $fileContent = get-content $psFilePath
        $rawTokens = [system.management.automation.psparser]::Tokenize($filecontent, [ref]$parseErrors) 

        write-verbose "Parsed $($rawTokens.count) tokens"
        if ($parseErrors.count -gt 0) {
            write-warning "Parse errors have been found... I haven't seen any before, so I don't have a handler ready."
        }

        # Ignore empty results and token type that won't matter (Comments, etc)
        $tokens = $rawTokens | where-object { $_ -and "Comment", "NewLine" -inotcontains $_.Type}
        write-verbose "$($tokens.count) tokens accepted"

        # While we don't handle nested functions yet, this sets us up for it (as well as modules maybe if I get ambitious)
        # It will record the functions as we go, as well as the depth of our braces
        $context = new-object Collections.Stack

        # Run through our tokens, pulling out function definitions and calls
        $state = [mState]::init
        foreach ($token in $tokens) {
            $type = $token.Type  # Keyword, CommandArgument, GroupStart, Operator, etc
            $content = $token.Content # The text that comprises the token ("function", "{", etc)
            write-debug  "currentState:'$state' type:'$type' content:'$content'"
        
            switch ($state) {
                init {
                    if ($type -eq "Keyword" -and $content -eq "function") {
                        # Function name coming soon, prepare our context
                        $context.Push( [PSCustomObject]@{type = $content; name = ""; braceDepth = 0} )

                        # Move to the next state so we can catch the name
                        $state = [mState]::functionSeen
                        showContext -state $state -context $context
                    }
                } # switch init
        
                functionSeen {
                    if ($type -eq "CommandArgument") {
                        # We got our function Name... tweak our context, add it to the funcOrder tracker, and prepare to track what it calls
                        ($context.Peek()).Name = $Content
                        $funcOrder += $content
                        if (! $called.ContainsKey($Content)) { $called[$content] = @{} 
                        }

                        # Move to the next state, so we can watch braces go by and we see when we're out of our function definition
                        # As well as watching for function calls
                        $state = [mState]::functionNamed
                        showContext -state $state -context $context
                    } else {
                        # Guess you have some bad code, oh well... just start over. I'm not that worried about trying to make real sense of bad code
                        $state = [mState]::init
                        write-warning "Invalid function definition"
                        showContext -state $state -context $context
                    }
                } #switch functionSeen

                functionNamed {
                    if ($type -eq "GroupStart" -and "{", "@{" -contains $content) {
                        # Opening a scope
                        ($context.Peek()).braceDepth++ 
                        showContext -state $state -context $context
                    } elseif ($type -eq "GroupEnd" -and $content -eq "}") {
                        # Closing a scope
                        ($context.Peek()).braceDepth--; 
                        showContext -state $state -context $context

                        # If we've closed out our last scope (ie, done with the function)...
                        if ( ($context.Peek()).braceDepth -lt 1 ) {
                            # Remove the function context
                            $context.Pop() | out-null

                            # if we're out of all our functions, go back to init state (this is for nested functions)
                            # otherwise, keep cycling until we're done with the outermost function
                            if ($context.count -eq 0) {
                                $state = [mState]::init
                                showContext -state $state -context $context
                            } else {
                                $state = [mState]::functionNamed
                                showContext -state $state -context $context
                            }
                        } 
                    } elseif ($type -eq "Command") {
                        write-verbose "    Command found: $content"

                        # Record the fact that function $func called command $content
                        $func = ($context.Peek()).Name
                        $called[$func][$content] = $true
                    } elseif ($type -eq "Keyword" -and $content -eq "function") {
                        $context.Push( [PSCustomObject]@{type = $content; name = ""; braceDepth = 0} )
                        $state = [mState]::functionSeen
                        showContext -state $state -context $context
                    } else {
                        #ignore
                    }
                } # switch functionNamed
        
                default {
                    # We should really never get here, but again, I'm not too worried about problems yet
                    write-warning "$([int]$state) : $([mState]::init) : $([mState]::init -eq $state)"
                } # switch default
            } # switch
        } # foreach token

    } # Process Block



    End {
        if ($dontRestrainGraphToProvidedFunctions) {
            # Go ahead and graph everything... could get ugly
            $constrainedCalled = $called
        } else {
            # We don't want all commands, just those within the provided files, so trim the stuff we didn't process out
            $constrainedCalled = @{}
            foreach ($func in $funcOrder) {
                $calledFuncs = $called[$func].Keys | sort-object -Unique | where-object { $called.containsKey($_) }
                $constrainedCalled[$func] = @{}
                $calledFuncs | ForEach-Object {
                    $constrainedCalled[$func][$_] = $true
                }
            }
        }
        
        if ($OutputFormat) {
            $g = graph "file" {
                $funcOrder | foreach-object { node $_}
            
                foreach ($func in $funcOrder) {
                    $calledFuncs = $constrainedCalled[$func].Keys
                    foreach ($targ in $calledFuncs) {
                        edge $func, $targ
                    }
                }    
            }
            
            if (! $DestinationPath) {
                $DestinationPath = "./sample.$($OutputFormat)"
            }
            $g | Export-PSGraph -DestinationPath $DestinationPath -OutputFormat $OutputFormat -LayoutEngine $LayoutEngine -ShowGraph:(! $HideGraph)
        }

        # Prepare a list of who called what
        $entries = @()
        foreach ($func in $funcOrder) {
            $calledFuncs = $constrainedCalled[$func].Keys
            $entries += [PSCustomObject]@{
                caller = $func
                called = ($calledFuncs -join ", ")
            }
        }
        
        $entries | format-table -auto
    } # End Block
}
