module Flags exposing (modelFromFlags)

import Accounting
import Json.Decode as Decode
import Ledger
import Model exposing (Model)
import Tutorial
import Update.LedgerData as LedgerData


modelFromFlags : Decode.Value -> Model
modelFromFlags flags =
    let
        tutorialState : Model.TutorialState
        tutorialState =
            Tutorial.decodeTutorialStateFromFlags flags

        initialModel : Model
        initialModel =
            Model.initial

        filterWindow : Accounting.FilterWindow
        filterWindow =
            Decode.decodeValue (Decode.field "filterWindow" Decode.string) flags
                |> Result.map Accounting.filterWindowFromString
                |> Result.withDefault initialModel.filterWindow

        colorScheme : Model.ColorScheme
        colorScheme =
            Decode.decodeValue (Decode.field "colorScheme" Decode.string) flags
                |> Result.map Model.colorSchemeFromString
                |> Result.withDefault initialModel.colorScheme

        baseModel : Model
        baseModel =
            { initialModel
                | tutorialState = tutorialState
                , filterWindow = filterWindow
                , colorScheme = colorScheme
            }

        ledgerResult : Result String Ledger.LedgerData
        ledgerResult =
            case Decode.decodeValue (Decode.field "ledger" Decode.value) flags of
                Ok ledgerValue ->
                    Ledger.decodeLedger ledgerValue

                Err _ ->
                    Ledger.decodeLedger flags
    in
    case ledgerResult of
        Ok ledger ->
            LedgerData.apply ledger baseModel

        Err _ ->
            baseModel
