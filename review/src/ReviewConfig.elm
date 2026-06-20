module ReviewConfig exposing (config)

import NoConfusingPrefixOperator
import NoDeprecated
import NoExposingEverything
import NoImportingEverything
import NoMissingTypeAnnotation
import NoMissingTypeAnnotationInLetIn
import NoMissingTypeExpose
import NoPrematureLetComputation
import NoUnused.CustomTypeConstructorArgs
import NoUnused.CustomTypeConstructors
import NoUnused.Dependencies
import NoUnused.Exports
import NoUnused.Modules
import NoUnused.Parameters
import NoUnused.Patterns
import NoUnused.Variables
import Review.Rule exposing (Rule)
import Simplify


config : List Rule
config =
    [ NoUnused.Variables.rule
    , NoUnused.Patterns.rule
    , NoUnused.Parameters.rule
    , NoUnused.Exports.rule
    , NoUnused.Modules.rule
    , NoUnused.Dependencies.rule
    , NoUnused.CustomTypeConstructors.rule []
    , NoUnused.CustomTypeConstructorArgs.rule
    , NoMissingTypeAnnotation.rule
    , NoMissingTypeAnnotationInLetIn.rule
    , NoMissingTypeExpose.rule
    , NoPrematureLetComputation.rule
    , NoDeprecated.rule NoDeprecated.defaults
    , NoExposingEverything.rule
    , NoImportingEverything.rule []
    , NoConfusingPrefixOperator.rule
    , Simplify.rule Simplify.defaults
    ]
