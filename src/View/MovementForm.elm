module View.MovementForm exposing (Config, preSaveWarning, showsExchangeRate, view)

import Accounting exposing (Account, Currency(..), Form, Movement, MovementType(..), currencyToString, movementTypeToString)
import Api.Dolar exposing (ExchangeRateStatus(..))
import Html exposing (Html, button, div, input, label, option, p, section, select, span, strong, text)
import Html.Attributes exposing (attribute, autofocus, checked, class, classList, name, step, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import InvoiceAllocation
import InvoiceReport
import Time
import Util.Date as Date
import Util.Format exposing (formatMoney, formatNumber)


type alias Config msg =
    { form : Form
    , accounts : List Account
    , movements : List Movement
    , exchangeRate : Float
    , exchangeRateStatus : ExchangeRateStatus
    , zone : Time.Zone
    , error : String
    , onDescription : String -> msg
    , onAmount : String -> msg
    , onAccount : String -> msg
    , onCreateAccount : msg
    , onCurrency : String -> msg
    , onDate : String -> msg
    , onMovementType : MovementType -> msg
    , onRelatedToInvoice : Bool -> msg
    , onDocumentNumber : String -> msg
    , onToggleAllocationTarget : String -> Bool -> msg
    , onSubmit : msg
    , onCancel : msg
    }


isInvoiceType : MovementType -> Bool
isInvoiceType movementType =
    movementType == SupplierInvoiceMovement || movementType == SupplierCreditNoteMovement


isCashflowType : MovementType -> Bool
isCashflowType movementType =
    movementType == ExpenseMovement || movementType == IncomeMovement


relatedCashflowPickerReplacesDescription : Form -> Bool
relatedCashflowPickerReplacesDescription form =
    isCashflowType form.movementType && form.relatedToInvoice


dateLabel : Form -> String
dateLabel form =
    if isInvoiceType form.movementType then
        "Vencimiento"

    else
        "Fecha"


submitButtonLabel : Form -> String
submitButtonLabel form =
    case form.movementType of
        ExpenseMovement ->
            "Registrar gasto"

        IncomeMovement ->
            "Registrar ingreso"

        SupplierInvoiceMovement ->
            "Registrar factura"

        SupplierCreditNoteMovement ->
            "Registrar nota de crédito"


relatedToInvoiceLabel : MovementType -> String
relatedToInvoiceLabel movementType =
    case movementType of
        IncomeMovement ->
            "Reembolso por nota de crédito"

        _ ->
            "Relacionado a factura"


showsExchangeRate : Form -> Bool
showsExchangeRate form =
    not (isInvoiceType form.movementType)


preSaveWarning : Float -> List Account -> List Movement -> Form -> Maybe String
preSaveWarning exchangeRate accounts movements form =
    case Accounting.buildMovement exchangeRate "preview-warning" accounts form of
        Ok movement ->
            warningForMovement movements (resolvePreviewMovement movements movement)

        Err _ ->
            Nothing


resolvePreviewMovement : List Movement -> Movement -> Movement
resolvePreviewMovement movements movement =
    if movement.relatedToInvoice && movement.allocationIntent == Nothing then
        { movement | allocationIntent = InvoiceAllocation.resolveAutoTargets movements movement }

    else
        movement


warningForMovement : List Movement -> Movement -> Maybe String
warningForMovement movements movement =
    case movement.movementType of
        ExpenseMovement ->
            if movement.relatedToInvoice then
                relatedCashflowWarning
                    { targetType = SupplierInvoiceMovement
                    , noCandidates = "Este pago está marcado para aplicarse a facturas, pero no hay facturas elegibles en esta cuenta. Puedes guardarlo, pero no quedará aplicado a ninguna factura."
                    , overAllocated = "Estás pagando más de lo pendiente en las facturas seleccionadas. El sobrante quedará como sobrepago en la factura más antigua seleccionada."
                    , underAllocated = "El pago no alcanza para cubrir todas las facturas seleccionadas. Se aplicará primero a las más antiguas y quedará saldo pendiente."
                    }
                    movements
                    movement

            else
                Nothing

        IncomeMovement ->
            if movement.relatedToInvoice then
                relatedCashflowWarning
                    { targetType = SupplierCreditNoteMovement
                    , noCandidates = "Este cobro está marcado para aplicarse a notas de crédito, pero no hay notas de crédito elegibles en esta cuenta. Puedes guardarlo, pero no quedará aplicado a ninguna nota de crédito."
                    , overAllocated = "Estás cobrando más de lo pendiente en las notas de crédito seleccionadas. El sobrante quedará como cobro en exceso en la nota de crédito más antigua seleccionada."
                    , underAllocated = "El cobro no alcanza para cubrir todas las notas de crédito seleccionadas. Se aplicará primero a las más antiguas y quedará saldo pendiente."
                    }
                    movements
                    movement

            else
                Nothing

        SupplierCreditNoteMovement ->
            creditNoteWarning movements movement

        SupplierInvoiceMovement ->
            Nothing


relatedCashflowWarning :
    { targetType : MovementType
    , noCandidates : String
    , overAllocated : String
    , underAllocated : String
    }
    -> List Movement
    -> Movement
    -> Maybe String
relatedCashflowWarning labels movements movement =
    let
        eligibleTargets : List Movement
        eligibleTargets =
            movements
                |> List.filter (eligibleRelatedCashflowTarget labels.targetType movement)

        selectedTargets : List Movement
        selectedTargets =
            selectedTargetMovements eligibleTargets movement
    in
    if List.isEmpty selectedTargets then
        if List.isEmpty eligibleTargets then
            Just labels.noCandidates

        else
            Nothing

    else
        amountComparisonWarning labels.overAllocated labels.underAllocated movements movement selectedTargets


creditNoteWarning : List Movement -> Movement -> Maybe String
creditNoteWarning movements movement =
    let
        eligibleTargets : List Movement
        eligibleTargets =
            movements
                |> List.filter (eligibleCreditNoteTarget movement)

        selectedTargets : List Movement
        selectedTargets =
            selectedTargetMovements eligibleTargets movement
    in
    if List.isEmpty selectedTargets then
        Nothing

    else
        amountComparisonWarning
            "La nota de crédito supera lo pendiente en las facturas seleccionadas. El sobrante quedará como crédito en exceso en la factura más antigua seleccionada."
            "La nota de crédito no alcanza para compensar todas las facturas seleccionadas. Se aplicará primero a las más antiguas y quedará saldo pendiente."
            movements
            movement
            selectedTargets


amountComparisonWarning : String -> String -> List Movement -> Movement -> List Movement -> Maybe String
amountComparisonWarning overAllocated underAllocated movements movement selectedTargets =
    let
        activeMovements : List Movement
        activeMovements =
            List.filter (\item -> item.deletedAt == Nothing && item.id /= movement.id) movements

        existingAllocations : List InvoiceAllocation.Allocation
        existingAllocations =
            InvoiceAllocation.allocate activeMovements

        remainingSelectedInSourceCurrency : Float
        remainingSelectedInSourceCurrency =
            selectedTargets
                |> List.map (remainingDueInSourceCurrency existingAllocations movement)
                |> List.sum

        sourceAmount : Float
        sourceAmount =
            abs movement.inputAmount

        tolerance : Float
        tolerance =
            toleranceFor movement.inputCurrency movement.exchangeRate
    in
    if sourceAmount > remainingSelectedInSourceCurrency + tolerance then
        Just overAllocated

    else if remainingSelectedInSourceCurrency > sourceAmount + tolerance then
        Just underAllocated

    else
        Nothing


remainingDueInSourceCurrency : List InvoiceAllocation.Allocation -> Movement -> Movement -> Float
remainingDueInSourceCurrency allocations source target =
    let
        remainingDue : Float
        remainingDue =
            targetSettlement allocations target
                |> .remainingDue
    in
    convertAmount source.exchangeRate target.inputCurrency source.inputCurrency remainingDue


targetSettlement : List InvoiceAllocation.Allocation -> Movement -> InvoiceAllocation.DocumentSettlement
targetSettlement allocations target =
    case target.movementType of
        SupplierCreditNoteMovement ->
            InvoiceAllocation.creditNoteSettlementFor allocations target

        _ ->
            InvoiceAllocation.invoiceSettlementFor allocations target


eligibleRelatedCashflowTarget : MovementType -> Movement -> Movement -> Bool
eligibleRelatedCashflowTarget targetType source target =
    target.deletedAt
        == Nothing
        && target.accountId
        == source.accountId
        && target.movementType
        == targetType


eligibleCreditNoteTarget : Movement -> Movement -> Bool
eligibleCreditNoteTarget source target =
    target.deletedAt
        == Nothing
        && target.accountId
        == source.accountId
        && target.movementType
        == SupplierInvoiceMovement
        && target.inputCurrency
        == source.inputCurrency


selectedTargetMovements : List Movement -> Movement -> List Movement
selectedTargetMovements eligibleTargets movement =
    targetIds movement
        |> List.filterMap (findMovementById eligibleTargets)


targetIds : Movement -> List String
targetIds movement =
    movement.allocationIntent
        |> Maybe.map .targetIds
        |> Maybe.withDefault []


findMovementById : List Movement -> String -> Maybe Movement
findMovementById movements movementId =
    movements
        |> List.filter (\movement -> movement.id == movementId)
        |> List.head


convertAmount : Float -> Currency -> Currency -> Float -> Float
convertAmount exchangeRate fromCurrency toCurrency amount =
    case ( fromCurrency, toCurrency ) of
        ( ARS, ARS ) ->
            amount

        ( USD, USD ) ->
            amount

        ( ARS, USD ) ->
            amount / exchangeRate

        ( USD, ARS ) ->
            amount * exchangeRate


toleranceFor : Currency -> Float -> Float
toleranceFor currency exchangeRate =
    case currency of
        USD ->
            1

        ARS ->
            exchangeRate


view : Config msg -> Html msg
view config =
    let
        selectedAccountId : String
        selectedAccountId =
            selectedOrDefaultAccountId config.form.accountId config.accounts

        editing : Bool
        editing =
            config.form.editingId /= Nothing

        warningText : Maybe String
        warningText =
            preSaveWarning config.exchangeRate config.accounts config.movements config.form
    in
    section [ class "panel movement-panel" ]
        [ Html.h2 [ class "section-title movement-title" ] [ text "Registrar movimiento" ]
        , Html.form [ class "form-grid", attribute "data-tutorial" "movement-form", onSubmit config.onSubmit ]
            [ label []
                [ text "Importe"
                , input
                    [ class "amount-input"
                    , type_ "number"
                    , attribute "inputmode" "decimal"
                    , attribute "autocomplete" "off"
                    , attribute "aria-label" "Importe del movimiento"
                    , attribute "min" "0.01"
                    , step "0.01"
                    , attribute "data-tutorial" "movement-amount"
                    , autofocus True
                    , value config.form.amount
                    , onInput config.onAmount
                    ]
                    []
                ]
            , div [ class "movement-type" ]
                [ span [ class "movement-type__label" ] [ text "Tipo" ]
                , label
                    [ class "movement-type__option"
                    , classList [ ( "movement-type__option--active", config.form.movementType == ExpenseMovement ) ]
                    ]
                    [ input
                        [ type_ "radio"
                        , name "movement-type"
                        , value (movementTypeToString ExpenseMovement)
                        , checked (config.form.movementType == ExpenseMovement)
                        , onClick (config.onMovementType ExpenseMovement)
                        ]
                        []
                    , span [] [ text "Gasto" ]
                    ]
                , label
                    [ class "movement-type__option"
                    , classList [ ( "movement-type__option--active", config.form.movementType == IncomeMovement ) ]
                    ]
                    [ input
                        [ type_ "radio"
                        , name "movement-type"
                        , value (movementTypeToString IncomeMovement)
                        , checked (config.form.movementType == IncomeMovement)
                        , onClick (config.onMovementType IncomeMovement)
                        ]
                        []
                    , span [] [ text "Ingreso" ]
                    ]
                , label
                    [ class "movement-type__option"
                    , classList [ ( "movement-type__option--active", config.form.movementType == SupplierInvoiceMovement ) ]
                    ]
                    [ input
                        [ type_ "radio"
                        , name "movement-type"
                        , value (movementTypeToString SupplierInvoiceMovement)
                        , checked (config.form.movementType == SupplierInvoiceMovement)
                        , onClick (config.onMovementType SupplierInvoiceMovement)
                        ]
                        []
                    , span [] [ text "Factura" ]
                    ]
                , label
                    [ class "movement-type__option"
                    , classList [ ( "movement-type__option--active", config.form.movementType == SupplierCreditNoteMovement ) ]
                    ]
                    [ input
                        [ type_ "radio"
                        , name "movement-type"
                        , value (movementTypeToString SupplierCreditNoteMovement)
                        , checked (config.form.movementType == SupplierCreditNoteMovement)
                        , onClick (config.onMovementType SupplierCreditNoteMovement)
                        ]
                        []
                    , span [] [ text "N. cred." ]
                    ]
                ]
            , if isInvoiceType config.form.movementType then
                label [ class "document-number-field" ]
                    [ text "Número"
                    , input
                        [ class "document-number-field__input"
                        , type_ "text"
                        , value config.form.documentNumber
                        , onInput config.onDocumentNumber
                        ]
                        []
                    ]

              else
                text ""
            , if relatedCashflowPickerReplacesDescription config.form then
                text ""

              else
                label [ class "description-field" ]
                    [ text "Descripción"
                    , input [ class "description-field__input", type_ "text", value config.form.description, onInput config.onDescription ] []
                    ]
            , label []
                [ text "Cuenta"
                , accountControl config selectedAccountId
                ]
            , div [ class "two-col" ]
                [ label []
                    [ text (dateLabel config.form)
                    , input [ type_ "date", value config.form.date, onInput config.onDate ] []
                    ]
                , label []
                    [ text "Divisa"
                    , select [ value (currencyToString config.form.currency), onInput config.onCurrency ]
                        [ option [ value "ARS" ] [ text "ARS" ]
                        , option [ value "USD" ] [ text "U$D" ]
                        ]
                    ]
                ]
            , if isCashflowType config.form.movementType && not editing then
                label [ class "related-to-invoice-field" ]
                    [ input
                        [ type_ "checkbox"
                        , checked config.form.relatedToInvoice
                        , onClick (config.onRelatedToInvoice (not config.form.relatedToInvoice))
                        ]
                        []
                    , span [] [ text (relatedToInvoiceLabel config.form.movementType) ]
                    ]

              else
                text ""
            , allocationPicker config selectedAccountId
            , if showsExchangeRate config.form then
                exchangeRateView config

              else
                text ""
            , case warningText of
                Just warning ->
                    p [ class "movement-warning" ] [ text warning ]

                Nothing ->
                    text ""
            , if config.error == "" then
                text ""

              else
                p [ class "error" ] [ text config.error ]
            , let
                buttonText : String
                buttonText =
                    if editing then
                        "Guardar cambios"

                    else
                        submitButtonLabel config.form
              in
              button [ class "primary primary--movement", type_ "submit" ] [ text buttonText ]
            , if editing then
                button [ class "cancel-button", type_ "button", onClick config.onCancel ] [ text "Cancelar" ]

              else
                text ""
            ]
        ]


type PickerMode
    = ExpenseInvoiceTargets
    | IncomeCreditNoteTargets
    | CreditNoteInvoiceTargets


allocationPicker : Config msg -> String -> Html msg
allocationPicker config selectedAccountId =
    case pickerMode config.form of
        Nothing ->
            text ""

        Just mode ->
            let
                rows : List InvoiceReport.DocumentRow
                rows =
                    allocationRows config selectedAccountId mode
            in
            div [ class "allocation-picker" ]
                [ div [ class "allocation-picker__header" ]
                    [ strong [] [ text (pickerTitle mode) ]
                    , span [] [ text (pickerHelp mode) ]
                    ]
                , if List.isEmpty rows then
                    p [ class "allocation-picker__empty" ] [ text (pickerEmptyText mode) ]

                  else
                    div [ class "allocation-picker__list" ]
                        (List.map (allocationTargetRow config) rows)
                ]


pickerMode : Form -> Maybe PickerMode
pickerMode form =
    case form.movementType of
        ExpenseMovement ->
            if form.relatedToInvoice then
                Just ExpenseInvoiceTargets

            else
                Nothing

        IncomeMovement ->
            if form.relatedToInvoice then
                Just IncomeCreditNoteTargets

            else
                Nothing

        SupplierCreditNoteMovement ->
            Just CreditNoteInvoiceTargets

        SupplierInvoiceMovement ->
            Nothing


allocationRows : Config msg -> String -> PickerMode -> List InvoiceReport.DocumentRow
allocationRows config selectedAccountId mode =
    let
        candidates : List Movement
        candidates =
            config.movements
                |> List.filter (eligibleAllocationTarget config.form selectedAccountId mode)
                |> List.sortWith compareByDateThenId
    in
    InvoiceReport.build config.movements candidates []
        |> .rows
        |> List.sortWith compareDocumentRowsByDateThenId


eligibleAllocationTarget : Form -> String -> PickerMode -> Movement -> Bool
eligibleAllocationTarget form selectedAccountId mode movement =
    movement.deletedAt
        == Nothing
        && movement.accountId
        == selectedAccountId
        && movement.movementType
        == targetMovementType mode
        && (case mode of
                CreditNoteInvoiceTargets ->
                    movement.inputCurrency == form.currency

                _ ->
                    True
           )


targetMovementType : PickerMode -> MovementType
targetMovementType mode =
    case mode of
        ExpenseInvoiceTargets ->
            SupplierInvoiceMovement

        IncomeCreditNoteTargets ->
            SupplierCreditNoteMovement

        CreditNoteInvoiceTargets ->
            SupplierInvoiceMovement


allocationTargetRow : Config msg -> InvoiceReport.DocumentRow -> Html msg
allocationTargetRow config documentRow =
    let
        movement : Movement
        movement =
            documentRow.movement

        selected : Bool
        selected =
            selectedTargetIds config.form
                |> List.member movement.id
    in
    label
        [ class "allocation-target-row"
        , classList [ ( "allocation-target-row--selected", selected ) ]
        ]
        [ input
            [ type_ "checkbox"
            , checked selected
            , onClick (config.onToggleAllocationTarget movement.id (not selected))
            ]
            []
        , div [ class "allocation-target-row__body" ]
            [ span [ class "allocation-target-row__title" ] [ text (documentTitle movement) ]
            , span [ class "allocation-target-row__meta" ]
                [ text
                    ("Vence "
                        ++ Date.formatDate Date.NumericDate movement.date
                        ++ " · "
                        ++ formatMoney movement.inputCurrency movement.inputAmount
                    )
                ]
            , span [ class "allocation-target-row__meta" ]
                [ text
                    ("Estado: "
                        ++ documentRow.statusLabel
                        ++ " · Pendiente: "
                        ++ formatMoney documentRow.settlement.currency documentRow.settlement.remainingDue
                    )
                ]
            ]
        ]


selectedTargetIds : Form -> List String
selectedTargetIds form =
    form.allocationIntent
        |> Maybe.map .targetIds
        |> Maybe.withDefault []


documentTitle : Movement -> String
documentTitle movement =
    case movement.documentNumber of
        Just number ->
            number

        Nothing ->
            "Sin número"


pickerTitle : PickerMode -> String
pickerTitle mode =
    case mode of
        ExpenseInvoiceTargets ->
            "Facturas a pagar"

        IncomeCreditNoteTargets ->
            "Notas de crédito a cobrar"

        CreditNoteInvoiceTargets ->
            "Facturas a compensar"


pickerHelp : PickerMode -> String
pickerHelp mode =
    case mode of
        ExpenseInvoiceTargets ->
            "Selecciona una o más facturas de esta cuenta."

        IncomeCreditNoteTargets ->
            "Selecciona una o más notas de crédito de esta cuenta."

        CreditNoteInvoiceTargets ->
            "Selecciona facturas de esta cuenta y divisa para aplicar la nota."


pickerEmptyText : PickerMode -> String
pickerEmptyText mode =
    case mode of
        ExpenseInvoiceTargets ->
            "No hay facturas en esta cuenta para seleccionar."

        IncomeCreditNoteTargets ->
            "No hay notas de crédito en esta cuenta para seleccionar."

        CreditNoteInvoiceTargets ->
            "No hay facturas de esta cuenta y divisa para compensar."


compareDocumentRowsByDateThenId : InvoiceReport.DocumentRow -> InvoiceReport.DocumentRow -> Order
compareDocumentRowsByDateThenId left right =
    compareByDateThenId left.movement right.movement


compareByDateThenId : Movement -> Movement -> Order
compareByDateThenId left right =
    case compare left.date right.date of
        EQ ->
            compare left.id right.id

        order ->
            order


selectedOrDefaultAccountId : String -> List Account -> String
selectedOrDefaultAccountId selectedAccountId accounts =
    if List.any (\account -> account.id == selectedAccountId) accounts then
        selectedAccountId

    else
        accounts
            |> List.head
            |> Maybe.map .id
            |> Maybe.withDefault ""


createAccountValue : String
createAccountValue =
    "__create_account__"


accountControl : Config msg -> String -> Html msg
accountControl config selectedAccountId =
    case config.accounts of
        [] ->
            button
                [ class "select-action"
                , type_ "button"
                , onClick config.onCreateAccount
                ]
                [ text "Agregar una cuenta" ]

        _ ->
            select
                [ value selectedAccountId
                , onInput
                    (\value ->
                        if value == createAccountValue then
                            config.onCreateAccount

                        else
                            config.onAccount value
                    )
                ]
                (List.map accountOption config.accounts
                    ++ [ option [ value createAccountValue ] [ text "Agregar una cuenta" ] ]
                )


accountOption : Account -> Html msg
accountOption account =
    option [ value account.id ] [ text account.name ]


exchangeRateView : Config msg -> Html msg
exchangeRateView config =
    let
        status : Maybe String
        status =
            case config.exchangeRateStatus of
                LoadingRate ->
                    Just "Buscando cotización bolsa para la fecha elegida..."

                LoadedRate ->
                    Nothing

                FailedRate message ->
                    Just message
    in
    div [ class "rate-status" ]
        (p [ class "rate-status__value" ]
            [ text ("Cot. Aprox: " ++ formatNumber config.exchangeRate ++ " ARS/USD") ]
            :: (case status of
                    Just message ->
                        [ p [ class "rate-status__meta" ] [ text message ] ]

                    Nothing ->
                        []
               )
        )
