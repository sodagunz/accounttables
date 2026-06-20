module Update.Accounts exposing (add, delete)

import Auth exposing (AuthState(..))
import Json.Encode as Encode
import Ledger
import Model exposing (Model, StorageMode(..), selectedLedgerId)


add : Model -> ( Model, Maybe Encode.Value )
add model =
    let
        name : String
        name =
            String.trim model.newAccountName
    in
    if name == "" then
        ( { model | accountError = "Ingresa un nombre." }, Nothing )

    else
        case model.authState of
            SignedIn _ ->
                if selectedLedgerId model == "" then
                    ( { model | accountError = "Selecciona un libro contable." }, Nothing )

                else
                    ( { model | newAccountName = "", accountError = "" }
                    , Just (Ledger.encodeAccountCreate (selectedLedgerId model) name)
                    )

            _ ->
                case model.storageMode of
                    LocalOnly ->
                        if selectedLedgerId model == "" then
                            ( { model | accountError = "No hay un libro local activo." }, Nothing )

                        else
                            ( { model | newAccountName = "", accountError = "" }
                            , Just (Ledger.encodeAccountCreate (selectedLedgerId model) name)
                            )

                    CloudSynced ->
                        ( { model | accountError = "Ingresa con Google para guardar cuentas en el libro contable." }, Nothing )


delete : String -> Model -> ( Model, Maybe Encode.Value )
delete accountId model =
    case model.authState of
        SignedIn _ ->
            if selectedLedgerId model == "" then
                ( { model | accountError = "Selecciona un libro contable." }, Nothing )

            else
                ( { model | accountError = "" }
                , Just (Ledger.encodeAccountDelete (selectedLedgerId model) accountId)
                )

        _ ->
            case model.storageMode of
                LocalOnly ->
                    if selectedLedgerId model == "" then
                        ( { model | accountError = "No hay un libro local activo." }, Nothing )

                    else
                        ( { model | accountError = "" }
                        , Just (Ledger.encodeAccountDelete (selectedLedgerId model) accountId)
                        )

                CloudSynced ->
                    ( { model | accountError = "Ingresa con Google para modificar cuentas del libro contable." }, Nothing )
