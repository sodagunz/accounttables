module Update.Expenses exposing (add)

import Accounting exposing (Expense)
import Auth exposing (AuthState(..))
import Json.Encode as Encode
import Ledger
import Model exposing (Model, selectedLedgerId)


add : Expense -> Model -> ( Model, Maybe Encode.Value )
add expense model =
    let
        updatedModel =
            { model
                | expenses = expense :: model.expenses
                , form =
                    { description = ""
                    , amount = ""
                    , accountId = model.form.accountId
                    , currency = model.form.currency
                    , date = model.form.date
                    , movementType = model.form.movementType
                    }
                , error = ""
            }
    in
    case model.authState of
        SignedIn _ ->
            if selectedLedgerId model == "" then
                ( { updatedModel | error = "Selecciona un libro contable." }, Nothing )

            else
                ( updatedModel
                , Just (Ledger.encodeExpense (selectedLedgerId model) expense)
                )

        _ ->
            ( updatedModel, Nothing )
