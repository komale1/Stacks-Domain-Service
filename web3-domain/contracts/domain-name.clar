;; Domain Name Service Contract

;; Error codes
(define-constant ERROR-DOMAIN-ALREADY-REGISTERED (err u100))
(define-constant ERROR-NOT-AUTHORIZED (err u101))
(define-constant ERROR-DOMAIN-NOT-REGISTERED (err u102))
(define-constant ERROR-INVALID-DOMAIN-NAME (err u103))
(define-constant ERROR-DOMAIN-EXPIRED (err u104))
(define-constant ERROR-INSUFFICIENT-PAYMENT (err u105))
(define-constant ERROR-INVALID-HASH (err u106))
(define-constant ERROR-INVALID-RECORD-TYPE (err u107))
(define-constant ERROR-INVALID-RECORD-CONTENT (err u108))

;; Configuration Constants
(define-constant REGISTRATION-PERIOD-IN-BLOCKS u52560) ;; ~1 year in blocks
(define-constant MIN-DOMAIN-LENGTH u3)
(define-constant MAX-DOMAIN-LENGTH u63)
(define-constant REGISTRATION-FEE-IN_MICRO_STX u100000) ;; in microSTX
(define-constant MAX_RECORD_TYPE_LENGTH u128)
(define-constant MAX_RECORD_CONTENT_LENGTH u256)

;; Data Maps
(define-map domain-ownership-registry
    {registered-domain-name: (string-ascii 64)}
    {
        current-owner: principal,
        expiration-block-height: uint,
        resolver-contract: (optional principal),
        initial-registration-block: uint,
        domain-commitment-hash: (buff 32)
    }
)

(define-map domain-registration-preorders
    {domain-commitment-hash: (buff 32)}
    {
        preorder-principal: principal,
        preorder-stx-amount: uint,
        preorder-creation-block: uint
    }
)

(define-map domain-dns-records
    {registered-domain-name: (string-ascii 64), dns-record-type: (string-ascii 128)}
    {dns-record-content: (string-ascii 256)}
)

;; Private validation functions
(define-private (is-valid-domain-name (domain-name-to-validate (string-ascii 64)))
    (and
        (>= (len domain-name-to-validate) MIN-DOMAIN-LENGTH)
        (<= (len domain-name-to-validate) MAX-DOMAIN-LENGTH)
    )
)

(define-private (is-valid-commitment-hash (hash-to-validate (buff 32)))
    (is-eq (len hash-to-validate) u32)
)

(define-private (is-valid-record-type (record-type-to-validate (string-ascii 128)))
    (and
        (>= (len record-type-to-validate) u1)
        (<= (len record-type-to-validate) MAX_RECORD_TYPE_LENGTH)
    )
)

(define-private (is-valid-record-content (content-to-validate (string-ascii 256)))
    (<= (len content-to-validate) MAX_RECORD_CONTENT_LENGTH)
)

;; Public functions

;; Preorder a domain (hash commitment)
(define-public (preorder-domain (domain-commitment-hash (buff 32)) (preorder-payment-ustx uint))
    (let
        (
            (preorder-data {
                preorder-principal: tx-sender,
                preorder-stx-amount: preorder-payment-ustx,
                preorder-creation-block: block-height
            })
        )
        (asserts! (is-valid-commitment-hash domain-commitment-hash) ERROR-INVALID-HASH)
        (asserts! (>= preorder-payment-ustx REGISTRATION-FEE-IN_MICRO_STX) ERROR-INSUFFICIENT-PAYMENT)
        (try! (stx-burn? preorder-payment-ustx tx-sender))
        (ok (map-set domain-registration-preorders {domain-commitment-hash: domain-commitment-hash} preorder-data))
    )
)

;; Register a domain name
(define-public (register-domain (requested-domain-name (string-ascii 64)) (commitment-salt (buff 32)))
    (let
        (
            (calculated-commitment-hash (hash160 commitment-salt))
            (preorder-data (unwrap! (map-get? domain-registration-preorders {domain-commitment-hash: calculated-commitment-hash}) ERROR-DOMAIN-NOT-REGISTERED))
            (new-registration-entry {
                current-owner: tx-sender,
                expiration-block-height: (+ block-height REGISTRATION-PERIOD-IN-BLOCKS),
                resolver-contract: none,
                initial-registration-block: block-height,
                domain-commitment-hash: calculated-commitment-hash
            })
        )
        (asserts! (is-valid-domain-name requested-domain-name) ERROR-INVALID-DOMAIN-NAME)
        (asserts! (is-valid-commitment-hash calculated-commitment-hash) ERROR-INVALID-HASH)
        (asserts! (is-none (map-get? domain-ownership-registry {registered-domain-name: requested-domain-name})) ERROR-DOMAIN-ALREADY-REGISTERED)
        (asserts! (is-eq tx-sender (get preorder-principal preorder-data)) ERROR-NOT-AUTHORIZED)
        
        (map-delete domain-registration-preorders {domain-commitment-hash: calculated-commitment-hash})
        (ok (map-set domain-ownership-registry {registered-domain-name: requested-domain-name} new-registration-entry))
    )
)

;; Transfer domain ownership
(define-public (transfer-domain (domain-name-to-transfer (string-ascii 64)) (new-owner-principal principal))
    (let
        (
            (current-registration (unwrap! (map-get? domain-ownership-registry {registered-domain-name: domain-name-to-transfer}) ERROR-DOMAIN-NOT-REGISTERED))
        )
        (asserts! (is-valid-domain-name domain-name-to-transfer) ERROR-INVALID-DOMAIN-NAME)
        (asserts! (is-eq tx-sender (get current-owner current-registration)) ERROR-NOT-AUTHORIZED)
        (asserts! (< block-height (get expiration-block-height current-registration)) ERROR-DOMAIN-EXPIRED)
        
        (ok (map-set domain-ownership-registry 
            {registered-domain-name: domain-name-to-transfer}
            (merge current-registration {current-owner: new-owner-principal})
        ))
    )
)

;; Renew domain registration
(define-public (renew-domain-registration (domain-name-to-renew (string-ascii 64)))
    (let
        (
            (current-registration (unwrap! (map-get? domain-ownership-registry {registered-domain-name: domain-name-to-renew}) ERROR-DOMAIN-NOT-REGISTERED))
        )
        (asserts! (is-valid-domain-name domain-name-to-renew) ERROR-INVALID-DOMAIN-NAME)
        (asserts! (is-eq tx-sender (get current-owner current-registration)) ERROR-NOT-AUTHORIZED)
        (try! (stx-burn? REGISTRATION-FEE-IN_MICRO_STX tx-sender))
        
        (ok (map-set domain-ownership-registry
            {registered-domain-name: domain-name-to-renew}
            (merge current-registration {
                expiration-block-height: (+ (get expiration-block-height current-registration) REGISTRATION-PERIOD-IN-BLOCKS)
            })
        ))
    )
)

;; Set resolver for domain
(define-public (set-domain-resolver (domain-name-to-update (string-ascii 64)) (new-resolver-principal (optional principal)))
    (let
        (
            (current-registration (unwrap! (map-get? domain-ownership-registry {registered-domain-name: domain-name-to-update}) ERROR-DOMAIN-NOT-REGISTERED))
        )
        (asserts! (is-valid-domain-name domain-name-to-update) ERROR-INVALID-DOMAIN-NAME)
        (asserts! (is-eq tx-sender (get current-owner current-registration)) ERROR-NOT-AUTHORIZED)
        (asserts! (< block-height (get expiration-block-height current-registration)) ERROR-DOMAIN-EXPIRED)
        
        (ok (map-set domain-ownership-registry
            {registered-domain-name: domain-name-to-update}
            (merge current-registration {resolver-contract: new-resolver-principal})
        ))
    )
)

;; Set domain records
(define-public (set-domain-record (domain-name-to-update (string-ascii 64)) (record-type (string-ascii 128)) (record-content (string-ascii 256)))
    (let
        (
            (current-registration (unwrap! (map-get? domain-ownership-registry {registered-domain-name: domain-name-to-update}) ERROR-DOMAIN-NOT-REGISTERED))
        )
        (asserts! (is-valid-domain-name domain-name-to-update) ERROR-INVALID-DOMAIN-NAME)
        (asserts! (is-valid-record-type record-type) ERROR-INVALID-RECORD-TYPE)
        (asserts! (is-valid-record-content record-content) ERROR-INVALID-RECORD-CONTENT)
        (asserts! (is-eq tx-sender (get current-owner current-registration)) ERROR-NOT-AUTHORIZED)
        (asserts! (< block-height (get expiration-block-height current-registration)) ERROR-DOMAIN-EXPIRED)
        
        (ok (map-set domain-dns-records
            {registered-domain-name: domain-name-to-update, dns-record-type: record-type}
            {dns-record-content: record-content}
        ))
    )
)

;; Read-only functions

;; Get domain details
(define-read-only (get-domain-details (requested-domain-name (string-ascii 64)))
    (map-get? domain-ownership-registry {registered-domain-name: requested-domain-name})
)

;; Get domain record
(define-read-only (get-domain-record (requested-domain-name (string-ascii 64)) (requested-record-type (string-ascii 128)))
    (map-get? domain-dns-records {registered-domain-name: requested-domain-name, dns-record-type: requested-record-type})
)

;; Check domain availability
(define-read-only (is-domain-name-available (requested-domain-name (string-ascii 64)))
    (is-none (map-get? domain-ownership-registry {registered-domain-name: requested-domain-name}))
)

;; Get domain expiration
(define-read-only (get-domain-expiration (requested-domain-name (string-ascii 64)))
    (match (map-get? domain-ownership-registry {registered-domain-name: requested-domain-name})
        domain-registration-details (ok (get expiration-block-height domain-registration-details))
        ERROR-DOMAIN-NOT-REGISTERED
    )
)