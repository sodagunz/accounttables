module Flags exposing (modelFromFlags)

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

        baseModel : Model
        baseModel =
            { initialModel | tutorialState = tutorialState }

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
