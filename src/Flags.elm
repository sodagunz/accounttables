module Flags exposing (modelFromFlags)

import Json.Decode as Decode
import Ledger
import Model exposing (Model)
import Tutorial
import Update.LedgerData as LedgerData


modelFromFlags : Decode.Value -> Model
modelFromFlags flags =
    let
        tutorialState =
            Tutorial.decodeTutorialStateFromFlags flags

        initialModel =
            Model.initial

        baseModel =
            { initialModel | tutorialState = tutorialState }

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
