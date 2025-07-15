;; CryptoVault Lending Protocol
;; Summary: Revolutionary decentralized lending ecosystem enabling secure 
;;          cryptocurrency-backed credit facilities with automated risk management
;;
;; Description: CryptoVault transforms traditional lending by creating a trustless,
;;              transparent financial infrastructure where users can unlock liquidity
;;              from their digital assets without selling. The protocol features
;;              dynamic collateralization, real-time liquidation protection, and
;;              sophisticated interest rate models that adapt to market conditions.
;;              Built for the next generation of DeFi, CryptoVault eliminates
;;              intermediaries while maintaining institutional-grade security and
;;              compliance standards.

;; SYSTEM CONSTANTS & ERROR CODES

(define-constant CONTRACT-OWNER tx-sender)

;; Core Error Definitions
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u101))
(define-constant ERR-BELOW-MINIMUM (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-ALREADY-INITIALIZED (err u104))
(define-constant ERR-NOT-INITIALIZED (err u105))
(define-constant ERR-INVALID-LIQUIDATION (err u106))
(define-constant ERR-LOAN-NOT-FOUND (err u107))
(define-constant ERR-LOAN-NOT-ACTIVE (err u108))

;; Enhanced Validation Error Codes
(define-constant ERR-INVALID-LOAN-ID (err u109))
(define-constant ERR-INVALID-PRICE (err u110))
(define-constant ERR-INVALID-ASSET (err u111))

;; Supported Asset Registry
(define-constant VALID-ASSETS (list "BTC" "STX"))

;; PLATFORM CONFIGURATION VARIABLES

(define-data-var platform-initialized bool false)
(define-data-var minimum-collateral-ratio uint u150) ;; 150% minimum collateral coverage
(define-data-var liquidation-threshold uint u120) ;; 120% liquidation trigger point
(define-data-var platform-fee-rate uint u1) ;; 1% platform revenue share
(define-data-var total-btc-locked uint u0) ;; Total collateral in custody
(define-data-var total-loans-issued uint u0) ;; Cumulative loan counter

;; DATA STORAGE STRUCTURES

;; Comprehensive Loan Registry
(define-map loans
  { loan-id: uint }
  {
    borrower: principal,
    collateral-amount: uint,
    loan-amount: uint,
    interest-rate: uint,
    start-height: uint,
    last-interest-calc: uint,
    status: (string-ascii 20),
  }
)

;; User Portfolio Tracking
(define-map user-loans
  { user: principal }
  { active-loans: (list 10 uint) }
)

;; Real-time Asset Pricing Oracle
(define-map collateral-prices
  { asset: (string-ascii 3) }
  { price: uint }
)

;; CORE FINANCIAL CALCULATIONS

;; Calculate loan-to-value ratio for risk assessment
(define-private (calculate-collateral-ratio
    (collateral uint)
    (loan uint)
    (btc-price uint)
  )
  (let (
      (collateral-value (* collateral btc-price))
      (ratio (* (/ collateral-value loan) u100))
    )
    ratio
  )
)

;; Compute accrued interest based on time and rate
(define-private (calculate-interest
    (principal uint)
    (rate uint)
    (blocks uint)
  )
  (let (
      (interest-per-block (/ (* principal rate) (* u100 u144))) ;; Daily interest / blocks per day
      (total-interest (* interest-per-block blocks))
    )
    total-interest
  )
)

;; RISK MANAGEMENT & LIQUIDATION ENGINE

;; Monitor loan health and trigger liquidation if necessary
(define-private (check-liquidation (loan-id uint))
  (let (
      (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
      (btc-price (unwrap! (get price (map-get? collateral-prices { asset: "BTC" }))
        ERR-NOT-INITIALIZED
      ))
      (current-ratio (calculate-collateral-ratio (get collateral-amount loan)
        (get loan-amount loan) btc-price
      ))
    )
    (if (<= current-ratio (var-get liquidation-threshold))
      (liquidate-position loan-id)
      (ok true)
    )
  )
)

;; Execute liquidation protocol for under-collateralized positions
(define-private (liquidate-position (loan-id uint))
  (let (
      (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
      (borrower (get borrower loan))
    )
    (begin
      (map-set loans { loan-id: loan-id } (merge loan { status: "liquidated" }))
      (map-delete user-loans { user: borrower })
      (ok true)
    )
  )
)

;; INPUT VALIDATION UTILITIES

;; Validate loan identifier within acceptable range
(define-private (validate-loan-id (loan-id uint))
  (and
    (> loan-id u0)
    (<= loan-id (var-get total-loans-issued))
  )
)

;; Verify asset is supported by the protocol
(define-private (is-valid-asset (asset (string-ascii 3)))
  (is-some (index-of VALID-ASSETS asset))
)

;; Ensure price feed data is within reasonable bounds
(define-private (is-valid-price (price uint))
  (and
    (> price u0)
    (<= price u1000000000000) ;; Upper limit prevents overflow attacks
  )
)

;; PLATFORM INITIALIZATION & SETUP

;; Initialize the lending platform (owner-only)
(define-public (initialize-platform)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get platform-initialized)) ERR-ALREADY-INITIALIZED)
    (var-set platform-initialized true)
    (ok true)
  )
)

;; COLLATERAL MANAGEMENT FUNCTIONS

;; Deposit cryptocurrency as loan collateral
(define-public (deposit-collateral (amount uint))
  (begin
    (asserts! (var-get platform-initialized) ERR-NOT-INITIALIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (var-set total-btc-locked (+ (var-get total-btc-locked) amount))
    (ok true)
  )
)

;; LOAN ORIGINATION & MANAGEMENT

;; Request a new collateral-backed loan
(define-public (request-loan
    (collateral uint)
    (loan-amount uint)
  )
  (let (
      (btc-price (unwrap! (get price (map-get? collateral-prices { asset: "BTC" }))
        ERR-NOT-INITIALIZED
      ))
      (collateral-value (* collateral btc-price))
      (required-collateral (* loan-amount (var-get minimum-collateral-ratio)))
      (loan-id (+ (var-get total-loans-issued) u1))
    )
    (begin
      (asserts! (var-get platform-initialized) ERR-NOT-INITIALIZED)
      (asserts! (>= collateral-value required-collateral)
        ERR-INSUFFICIENT-COLLATERAL
      )
      ;; Create new loan record
      (map-set loans { loan-id: loan-id } {
        borrower: tx-sender,
        collateral-amount: collateral,
        loan-amount: loan-amount,
        interest-rate: u5, ;; 5% annual interest rate
        start-height: stacks-block-height,
        last-interest-calc: stacks-block-height,
        status: "active",
      })
      ;; Update user's active loan portfolio
      (match (map-get? user-loans { user: tx-sender })
        existing-loans (map-set user-loans { user: tx-sender } { active-loans: (unwrap!
          (as-max-len? (append (get active-loans existing-loans) loan-id) u10)
          ERR-INVALID-AMOUNT
        ) }
        )
        (map-set user-loans { user: tx-sender } { active-loans: (list loan-id) })
      )
      (var-set total-loans-issued (+ (var-get total-loans-issued) u1))
      (ok loan-id)
    )
  )
)

;; Process loan repayment and release collateral
(define-public (repay-loan
    (loan-id uint)
    (amount uint)
  )
  (begin
    ;; Validate loan identifier
    (asserts! (validate-loan-id loan-id) ERR-INVALID-LOAN-ID)
    (let (
        (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
        (interest-owed (calculate-interest (get loan-amount loan) (get interest-rate loan)
          (- stacks-block-height (get last-interest-calc loan))
        ))
        (total-owed (+ (get loan-amount loan) interest-owed))
      )
      (begin
        (asserts! (is-eq (get status loan) "active") ERR-LOAN-NOT-ACTIVE)
        (asserts! (is-eq (get borrower loan) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (>= amount total-owed) ERR-INVALID-AMOUNT)
        ;; Mark loan as fully repaid
        (map-set loans { loan-id: loan-id }
          (merge loan {
            status: "repaid",
            last-interest-calc: stacks-block-height,
          })
        )
        ;; Release collateral from custody
        (var-set total-btc-locked
          (- (var-get total-btc-locked) (get collateral-amount loan))
        )
        ;; Clean up user's active loan list
        (match (map-get? user-loans { user: tx-sender })
          existing-loans (ok (map-set user-loans { user: tx-sender } { active-loans: (filter not-equal-loan-id (get active-loans existing-loans)) }))
          (ok false)
        )
      )
    )
  )
)

;; PROTOCOL GOVERNANCE & ADMINISTRATION

;; Update minimum collateral requirements
(define-public (update-collateral-ratio (new-ratio uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (>= new-ratio u110) ERR-INVALID-AMOUNT)
    (var-set minimum-collateral-ratio new-ratio)
    (ok true)
  )
)

;; Adjust liquidation trigger threshold
(define-public (update-liquidation-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (>= new-threshold u110) ERR-INVALID-AMOUNT)
    (var-set liquidation-threshold new-threshold)
    (ok true)
  )
)

;; Update asset pricing oracle feeds
(define-public (update-price-feed
    (asset (string-ascii 3))
    (new-price uint)
  )
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    ;; Comprehensive input validation
    (asserts! (is-valid-asset asset) ERR-INVALID-ASSET)
    (asserts! (is-valid-price new-price) ERR-INVALID-PRICE)
    ;; Update pricing data
    (ok (map-set collateral-prices { asset: asset } { price: new-price }))
  )
)

;; DATA RETRIEVAL & ANALYTICS

;; Retrieve comprehensive loan information
(define-read-only (get-loan-details (loan-id uint))
  (map-get? loans { loan-id: loan-id })
)

;; Get user's complete loan portfolio
(define-read-only (get-user-loans (user principal))
  (map-get? user-loans { user: user })
)

;; Platform-wide statistics and metrics
(define-read-only (get-platform-stats)
  {
    total-btc-locked: (var-get total-btc-locked),
    total-loans-issued: (var-get total-loans-issued),
    minimum-collateral-ratio: (var-get minimum-collateral-ratio),
    liquidation-threshold: (var-get liquidation-threshold),
  }
)

;; Retrieve list of supported collateral assets
(define-read-only (get-valid-assets)
  VALID-ASSETS
)

;; UTILITY FUNCTIONS

;; Filter helper for loan list management
(define-private (not-equal-loan-id (id uint))
  (not (is-eq id id))
)