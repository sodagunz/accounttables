module AccountingTest exposing (suite)

import Accounting exposing (Currency(..), MovementType(..))
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Accounting"
        [ test "converts USD expenses into negative ARS and USD cashflow" <|
            \_ ->
                Accounting.cashflowFor ExpenseMovement 1000 USD 2
                    |> Expect.equal { ars = -2000, usd = -2 }
        , test "builds an income movement from a valid form" <|
            \_ ->
                let
                    form =
                        { description = "  Venta  "
                        , amount = "1500"
                        , accountId = "cash"
                        , currency = ARS
                        , date = "2026-06-16"
                        , movementType = IncomeMovement
                        , editingId = Nothing
                        }

                    accounts =
                        [ { id = "cash", name = "Caja", deletedAt = Nothing } ]
                in
                case Accounting.buildMovement 1000 "movement-1" accounts form of
                    Ok movement ->
                        Expect.all
                            [ \actual -> Expect.equal "movement-1" actual.id
                            , \actual -> Expect.equal (Just "Venta") actual.description
                            , \actual -> Expect.equal "cash" actual.accountId
                            , \actual -> Expect.within (Expect.Absolute 0.0001) 1500 actual.ars
                            , \actual -> Expect.within (Expect.Absolute 0.0001) 1.5 actual.usd
                            , \actual -> Expect.equal IncomeMovement actual.movementType
                            ]
                            movement

                    Err error ->
                        Expect.fail error
        , test "rejects a deleted selected account" <|
            \_ ->
                let
                    form =
                        { description = "Pago"
                        , amount = "10"
                        , accountId = "deleted"
                        , currency = ARS
                        , date = "2026-06-16"
                        , movementType = ExpenseMovement
                        , editingId = Nothing
                        }

                    accounts =
                        [ { id = "deleted", name = "Vieja", deletedAt = Just "deleted" } ]
                in
                Accounting.buildMovement 1000 "movement-1" accounts form
                    |> Expect.equal (Err "Selecciona una cuenta.")
        ]
