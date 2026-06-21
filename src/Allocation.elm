module Allocation exposing
    ( AllocationIntent
    , AllocationStrategy(..)
    , AutoSelectionReason(..)
    , MigrationSelectionReason(..)
    , TargetSelectionSource(..)
    , allocationIntentDecoder
    , allocationIntentEncoder
    , encodeMaybeAllocationIntent
    )

import Json.Decode as Decode exposing (Decoder, field, list, string)
import Json.Decode.Pipeline exposing (custom, required)
import Json.Encode as Encode


type AllocationStrategy
    = OldestDueFirstThenOverpayOldest


type TargetSelectionSource
    = UserSelectedTargets
    | AutoSelectedTargets AutoSelectionReason
    | MigrationSelectedTargets MigrationSelectionReason
    | LegacyDynamicTargets


type AutoSelectionReason
    = AutoExactRemainingDueMatch
    | AutoAllOpenDocuments
    | AutoNoCandidates


type MigrationSelectionReason
    = MigrationImportedExplicitTargets
    | MigrationInferredFromDocumentNumber
    | MigrationInferredFromExactAmount
    | MigrationInferredFromLegacyBoolean


type alias AllocationIntent =
    { targetIds : List String
    , targetSelectionSource : TargetSelectionSource
    , strategy : AllocationStrategy
    }


encodeMaybeAllocationIntent : Maybe AllocationIntent -> Encode.Value
encodeMaybeAllocationIntent maybeIntent =
    case maybeIntent of
        Just intent ->
            allocationIntentEncoder intent

        Nothing ->
            Encode.null


allocationIntentEncoder : AllocationIntent -> Encode.Value
allocationIntentEncoder intent =
    let
        sourceFields : List ( String, Encode.Value )
        sourceFields =
            targetSelectionSourceFields intent.targetSelectionSource
    in
    Encode.object
        ([ ( "targetIds", Encode.list Encode.string intent.targetIds )
         , ( "strategy", Encode.string (allocationStrategyToString intent.strategy) )
         ]
            ++ sourceFields
        )


targetSelectionSourceFields : TargetSelectionSource -> List ( String, Encode.Value )
targetSelectionSourceFields source =
    case source of
        UserSelectedTargets ->
            [ ( "targetSelectionSource", Encode.string "user_selected" )
            , ( "autoSelectionReason", Encode.null )
            , ( "migrationSelectionReason", Encode.null )
            ]

        AutoSelectedTargets reason ->
            [ ( "targetSelectionSource", Encode.string "auto_selected" )
            , ( "autoSelectionReason", Encode.string (autoSelectionReasonToString reason) )
            , ( "migrationSelectionReason", Encode.null )
            ]

        MigrationSelectedTargets reason ->
            [ ( "targetSelectionSource", Encode.string "migration_selected" )
            , ( "autoSelectionReason", Encode.null )
            , ( "migrationSelectionReason", Encode.string (migrationSelectionReasonToString reason) )
            ]

        LegacyDynamicTargets ->
            [ ( "targetSelectionSource", Encode.string "legacy_dynamic" )
            , ( "autoSelectionReason", Encode.null )
            , ( "migrationSelectionReason", Encode.null )
            ]


allocationIntentDecoder : Decoder AllocationIntent
allocationIntentDecoder =
    Decode.succeed AllocationIntent
        |> required "targetIds" (list string)
        |> custom targetSelectionSourceDecoder
        |> required "strategy" allocationStrategyDecoder


targetSelectionSourceDecoder : Decoder TargetSelectionSource
targetSelectionSourceDecoder =
    field "targetSelectionSource" string
        |> Decode.andThen
            (\source ->
                case source of
                    "user_selected" ->
                        Decode.succeed UserSelectedTargets

                    "auto_selected" ->
                        Decode.map AutoSelectedTargets (field "autoSelectionReason" autoSelectionReasonDecoder)

                    "migration_selected" ->
                        Decode.map MigrationSelectedTargets (field "migrationSelectionReason" migrationSelectionReasonDecoder)

                    "legacy_dynamic" ->
                        Decode.succeed LegacyDynamicTargets

                    _ ->
                        Decode.fail ("Unknown allocation target selection source: " ++ source)
            )


allocationStrategyDecoder : Decoder AllocationStrategy
allocationStrategyDecoder =
    string
        |> Decode.andThen
            (\strategy ->
                case strategy of
                    "oldest_due_first_then_overpay_oldest" ->
                        Decode.succeed OldestDueFirstThenOverpayOldest

                    _ ->
                        Decode.fail ("Unknown allocation strategy: " ++ strategy)
            )


autoSelectionReasonDecoder : Decoder AutoSelectionReason
autoSelectionReasonDecoder =
    string
        |> Decode.andThen
            (\reason ->
                case reason of
                    "exact_remaining_due_match" ->
                        Decode.succeed AutoExactRemainingDueMatch

                    "all_open_documents" ->
                        Decode.succeed AutoAllOpenDocuments

                    "no_candidates" ->
                        Decode.succeed AutoNoCandidates

                    _ ->
                        Decode.fail ("Unknown auto-selection reason: " ++ reason)
            )


migrationSelectionReasonDecoder : Decoder MigrationSelectionReason
migrationSelectionReasonDecoder =
    string
        |> Decode.andThen
            (\reason ->
                case reason of
                    "imported_explicit_targets" ->
                        Decode.succeed MigrationImportedExplicitTargets

                    "inferred_from_document_number" ->
                        Decode.succeed MigrationInferredFromDocumentNumber

                    "inferred_from_exact_amount" ->
                        Decode.succeed MigrationInferredFromExactAmount

                    "inferred_from_legacy_boolean" ->
                        Decode.succeed MigrationInferredFromLegacyBoolean

                    _ ->
                        Decode.fail ("Unknown migration selection reason: " ++ reason)
            )


allocationStrategyToString : AllocationStrategy -> String
allocationStrategyToString strategy =
    case strategy of
        OldestDueFirstThenOverpayOldest ->
            "oldest_due_first_then_overpay_oldest"


autoSelectionReasonToString : AutoSelectionReason -> String
autoSelectionReasonToString reason =
    case reason of
        AutoExactRemainingDueMatch ->
            "exact_remaining_due_match"

        AutoAllOpenDocuments ->
            "all_open_documents"

        AutoNoCandidates ->
            "no_candidates"


migrationSelectionReasonToString : MigrationSelectionReason -> String
migrationSelectionReasonToString reason =
    case reason of
        MigrationImportedExplicitTargets ->
            "imported_explicit_targets"

        MigrationInferredFromDocumentNumber ->
            "inferred_from_document_number"

        MigrationInferredFromExactAmount ->
            "inferred_from_exact_amount"

        MigrationInferredFromLegacyBoolean ->
            "inferred_from_legacy_boolean"
