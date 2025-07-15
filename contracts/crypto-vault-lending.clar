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