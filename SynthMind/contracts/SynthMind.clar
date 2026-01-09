;; AI-Powered Synthetic Asset Management Contract
;; This contract enables creation and management of synthetic assets with AI price oracles and liquidations.

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-POSITION-NOT-FOUND (err u103))
(define-constant ERR-STALE-PRICE (err u104))
(define-constant ERR-LIQUIDATION-NOT-ALLOWED (err u105))
(define-constant ERR-CONTRACT-PAUSED (err u106))
(define-constant ERR-ORACLE-NOT-REGISTERED (err u107))
(define-constant ERR-EXCEEDS-MAX-POSITION (err u108))
(define-constant MIN-COLLATERAL-RATIO u150)
(define-constant LIQUIDATION-THRESHOLD u120)
(define-constant LIQUIDATION-BONUS u10)
(define-constant LIQUIDATION-PENALTY u5)
(define-constant ORACLE-STALENESS-LIMIT u100)
(define-constant MIN-ORACLE-CONFIDENCE u60)
(define-constant MAX-POSITION-PERCENTAGE u10)
(define-constant COOLDOWN-BLOCKS u10)
(define-constant MINTING-FEE-BPS u50)

;; data maps and vars
;; Tracks user positions with collateral and minted synthetics
(define-map user-positions principal
    {collateral-deposited: uint, synthetic-minted: uint, last-interaction-block: uint, position-health: uint, liquidation-protected: bool})
;; Authorized AI oracles for price feeds
(define-map authorized-oracles principal {is-active: bool, total-submissions: uint, credibility-score: uint})
;; Price feed submissions with confidence scores
(define-map price-feeds {asset-id: (string-ascii 10), submission-id: uint}
    {oracle: principal, price: uint, confidence: uint, timestamp: uint})
;; Liquidation event records
(define-map liquidation-history uint
    {user-liquidated: principal, liquidator: principal, collateral-seized: uint, debt-covered: uint, reward: uint, block-height: uint})
;; Global state variables
(define-data-var total-collateral uint u0)
(define-data-var total-synthetic-supply uint u0)
(define-data-var current-price uint u100000000)
(define-data-var last-price-update uint u0)
(define-data-var contract-paused bool false)
(define-data-var liquidation-nonce uint u0)
(define-data-var price-submission-nonce uint u0)

;; private functions
;; Calculate position health ratio as percentage
(define-private (calculate-position-health (collateral uint) (debt uint) (price uint))
    (if (is-eq debt u0) u999999 (/ (* (* collateral price) u100) (* debt u100000000))))
;; Calculate max mintable synthetics from collateral
(define-private (calculate-max-mintable (collateral uint) (price uint))
    (/ (* collateral price) (* MIN-COLLATERAL-RATIO u1000000)))
;; Validate if price data is fresh
(define-private (is-price-fresh (timestamp uint))
    (< (- block-height timestamp) ORACLE-STALENESS-LIMIT))
;; Check if position is below liquidation threshold
(define-private (is-liquidatable (health uint)) (< health LIQUIDATION-THRESHOLD))
;; Calculate liquidation reward with bonus
(define-private (calculate-liquidation-reward (collateral uint))
    (/ (* collateral (+ u100 LIQUIDATION-BONUS)) u100))

;; public functions
;; Register AI oracle for price feed submissions (owner only)
(define-public (register-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (map-set authorized-oracles oracle {is-active: true, total-submissions: u0, credibility-score: u100})
        (ok true)))
;; Emergency pause mechanism
(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set contract-paused true)
        (ok true)))
;; Resume operations
(define-public (resume-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set contract-paused false)
        (ok true)))

;; Deposit STX collateral for synthetic minting
(define-public (deposit-collateral (amount uint))
    (let ((current-position (default-to {collateral-deposited: u0, synthetic-minted: u0, last-interaction-block: u0, position-health: u999999, liquidation-protected: false}
                (map-get? user-positions tx-sender))))
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set user-positions tx-sender
            (merge current-position {collateral-deposited: (+ (get collateral-deposited current-position) amount), last-interaction-block: block-height}))
        (var-set total-collateral (+ (var-get total-collateral) amount))
        (ok amount)))

;; Mint synthetic assets against collateral with fee deduction
(define-public (mint-synthetic (amount uint))
    (let ((position (unwrap! (map-get? user-positions tx-sender) ERR-POSITION-NOT-FOUND))
          (price-at-mint (var-get current-price))
          (max-mintable (calculate-max-mintable (get collateral-deposited position) (var-get current-price)))
          (new-total-minted (+ (get synthetic-minted position) amount))
          (fee (/ (* amount MINTING-FEE-BPS) u10000)))
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= new-total-minted max-mintable) ERR-INSUFFICIENT-COLLATERAL)
        (asserts! (>= (- block-height (get last-interaction-block position)) COOLDOWN-BLOCKS) ERR-INVALID-AMOUNT)
        (let ((new-health (calculate-position-health (get collateral-deposited position) new-total-minted price-at-mint)))
            (map-set user-positions tx-sender
                (merge position {synthetic-minted: new-total-minted, position-health: new-health, last-interaction-block: block-height}))
            (var-set total-synthetic-supply (+ (var-get total-synthetic-supply) amount))
            (ok (- amount fee)))))

;; Submit AI price feed with confidence scoring (authorized oracles only)
(define-public (submit-price-feed (asset-id (string-ascii 10)) (price uint) (confidence uint))
    (let ((oracle-data (unwrap! (map-get? authorized-oracles tx-sender) ERR-ORACLE-NOT-REGISTERED))
          (submission-id (var-get price-submission-nonce)))
        (asserts! (get is-active oracle-data) ERR-NOT-AUTHORIZED)
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (>= confidence MIN-ORACLE-CONFIDENCE) ERR-INVALID-AMOUNT)
        (asserts! (> price u0) ERR-INVALID-AMOUNT)
        (map-set price-feeds {asset-id: asset-id, submission-id: submission-id}
            {oracle: tx-sender, price: price, confidence: confidence, timestamp: block-height})
        (map-set authorized-oracles tx-sender (merge oracle-data {total-submissions: (+ (get total-submissions oracle-data) u1)}))
        (var-set current-price price)
        (var-set last-price-update block-height)
        (var-set price-submission-nonce (+ submission-id u1))
        (ok submission-id)))

;; Liquidate undercollateralized positions with bonus rewards
(define-public (liquidate-position (user principal) (debt-to-cover uint))
    (let ((position (unwrap! (map-get? user-positions user) ERR-POSITION-NOT-FOUND))
          (price-at-liquidation (var-get current-price))
          (position-health (calculate-position-health (get collateral-deposited position) (get synthetic-minted position) price-at-liquidation))
          (liquidation-id (var-get liquidation-nonce)))
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (is-liquidatable position-health) ERR-LIQUIDATION-NOT-ALLOWED)
        (asserts! (is-price-fresh (var-get last-price-update)) ERR-STALE-PRICE)
        (asserts! (<= debt-to-cover (/ (get synthetic-minted position) u2)) ERR-INVALID-AMOUNT)
        (let ((collateral-value (/ (* debt-to-cover u100000000) price-at-liquidation))
              (liquidator-reward (calculate-liquidation-reward collateral-value))
              (penalty (/ (* collateral-value LIQUIDATION-PENALTY) u100)))
            (try! (as-contract (stx-transfer? liquidator-reward tx-sender tx-sender)))
            (map-set user-positions user
                (merge position {collateral-deposited: (- (get collateral-deposited position) (+ collateral-value penalty)),
                                synthetic-minted: (- (get synthetic-minted position) debt-to-cover), last-interaction-block: block-height}))
            (map-set liquidation-history liquidation-id
                {user-liquidated: user, liquidator: tx-sender, collateral-seized: collateral-value,
                 debt-covered: debt-to-cover, reward: liquidator-reward, block-height: block-height})
            (var-set liquidation-nonce (+ liquidation-id u1))
            (var-set total-synthetic-supply (- (var-get total-synthetic-supply) debt-to-cover))
            (ok liquidation-id))))
;; Get user position data
(define-read-only (get-user-position (user principal)) (ok (map-get? user-positions user)))
;; Get current price from AI oracles
(define-read-only (get-current-price) (ok (var-get current-price)))

;; Advanced multi-asset collateral position management with AI risk scoring and diversification analysis
;; This function enables users to create diversified collateral portfolios across multiple asset types,
;; calculates aggregate risk-weighted values, applies diversification bonuses to collateral requirements,
;; and determines optimal synthetic minting capacity through AI-driven risk assessment with correlation analysis
(define-public (manage-diversified-collateral-position 
    (collateral-types (list 5 (string-ascii 10)))
    (collateral-amounts (list 5 uint))
    (operation (string-ascii 10))
    (synthetic-amount uint)
    (risk-scores (list 5 uint)))
    (let ((user tx-sender)
          (position (default-to {collateral-deposited: u0, synthetic-minted: u0, last-interaction-block: u0,
                                position-health: u999999, liquidation-protected: false}
                                (map-get? user-positions user)))
          (num-assets (len collateral-types)))
        ;; Validate contract operational status and input parameters match requirements
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (is-eq (len collateral-amounts) num-assets) ERR-INVALID-AMOUNT)
        (asserts! (is-eq (len risk-scores) num-assets) ERR-INVALID-AMOUNT)
        (asserts! (> num-assets u1) ERR-INVALID-AMOUNT)
        (asserts! (is-price-fresh (var-get last-price-update)) ERR-STALE-PRICE)
        ;; Calculate aggregate collateral with risk-weighted adjustments and diversification benefits
        (let ((total-collateral-value (fold + collateral-amounts u0))
              (avg-risk-score (/ (fold + risk-scores u0) num-assets))
              (diversification-bonus (if (> num-assets u2) u10 u5))
              (adjusted-ratio (- MIN-COLLATERAL-RATIO diversification-bonus))
              (max-mintable (/ (* total-collateral-value (var-get current-price)) (* adjusted-ratio u1000000)))
              (projected-debt (if (is-eq operation "mint") (+ (get synthetic-minted position) synthetic-amount) (get synthetic-minted position)))
              (projected-collateral (+ (get collateral-deposited position) total-collateral-value))
              (new-health (calculate-position-health projected-collateral projected-debt (var-get current-price)))
              (position-percentage (/ (* projected-collateral u100) (var-get total-collateral))))
            ;; Validate operation meets safety thresholds and risk parameters
            (asserts! (<= position-percentage MAX-POSITION-PERCENTAGE) ERR-EXCEEDS-MAX-POSITION)
            (asserts! (>= new-health MIN-COLLATERAL-RATIO) ERR-INSUFFICIENT-COLLATERAL)
            (asserts! (<= synthetic-amount max-mintable) ERR-INSUFFICIENT-COLLATERAL)
            (asserts! (>= avg-risk-score u50) ERR-INVALID-AMOUNT)
            ;; Execute state changes and return comprehensive position analytics
            (if (is-eq operation "mint")
                (begin
                    (map-set user-positions user {collateral-deposited: projected-collateral, synthetic-minted: projected-debt,
                                                  last-interaction-block: block-height, position-health: new-health,
                                                  liquidation-protected: (> diversification-bonus u8)})
                    (var-set total-collateral (+ (var-get total-collateral) total-collateral-value))
                    (var-set total-synthetic-supply (+ (var-get total-synthetic-supply) synthetic-amount))
                    (ok {success: true, health-ratio: new-health, diversification-bonus: diversification-bonus,
                         max-additional-mintable: (- max-mintable synthetic-amount), avg-risk-score: avg-risk-score,
                         collateral-locked: projected-collateral}))
                (ok {success: true, health-ratio: new-health, diversification-bonus: diversification-bonus,
                     max-additional-mintable: max-mintable, avg-risk-score: avg-risk-score, collateral-locked: projected-collateral})))))



