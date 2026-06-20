module Update.Ledgers exposing (inviteGuest, removeGuest, rename, select)

import Json.Encode as Encode
import Ledger
import Model exposing (Model, StorageMode(..), ledgerNameFor, selectedLedgerId)


select : String -> Model -> Model
select ledgerId model =
    { model
        | currentLedgerId = ledgerId
        , ledgerName = ledgerNameFor ledgerId model.ledgers
        , ledgerLoadState = Ledger.Loading
        , expenses = []
        , accounts = []
        , error = ""
        , accountError = ""
        , ledgerError = ""
    }


inviteGuest : Model -> ( Model, Maybe Encode.Value )
inviteGuest model =
    let
        email : String
        email =
            String.toLower (String.trim model.inviteEmail)
    in
    if email == "" then
        ( { model | ledgerError = "Ingresa un email." }, Nothing )

    else if selectedLedgerId model == "" then
        ( { model | ledgerError = "Selecciona un libro contable." }, Nothing )

    else
        case model.storageMode of
            LocalOnly ->
                ( { model | ledgerError = "Ingresa con Google para invitar colaboradores." }, Nothing )

            CloudSynced ->
                ( { model | inviteEmail = "", ledgerError = "" }
                , Just (Ledger.encodeGuestInvite (selectedLedgerId model) email)
                )


removeGuest : String -> Model -> ( Model, Maybe Encode.Value )
removeGuest uid model =
    if selectedLedgerId model == "" then
        ( { model | ledgerError = "Selecciona un libro contable." }, Nothing )

    else
        ( { model | ledgerError = "" }
        , Just (Ledger.encodeGuestRemove (selectedLedgerId model) uid)
        )


rename : Model -> ( Model, Maybe Encode.Value )
rename model =
    let
        name : String
        name =
            String.trim model.ledgerName
    in
    if name == "" then
        ( { model | ledgerError = "Ingresa un nombre para el libro contable." }, Nothing )

    else if selectedLedgerId model == "" then
        ( { model | ledgerError = "Selecciona un libro contable." }, Nothing )

    else
        ( { model | ledgerName = name, ledgerError = "" }
        , Just (Ledger.encodeLedgerName (selectedLedgerId model) name)
        )
