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