;; ShiftHub - Decentralized Creator Economy Platform (Cleaned Version)

;; Error Constants
(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_INVALID_CONTENT (err u2))
(define-constant ERR_INVALID_DNA (err u3))
(define-constant ERR_INSUFFICIENT_INFLUENCE (err u4))
(define-constant ERR_CURATOR_NOT_FOUND (err u5))
(define-constant ERR_CONTENT_EXPIRED (err u6))
(define-constant ERR_INVALID_ENGAGEMENT (err u7))
(define-constant ERR_DUPLICATE_CURATION (err u8))
(define-constant ERR_INVALID_MERKLE_PROOF (err u9))
(define-constant ERR_INVALID_COMMITMENT (err u10))
(define-constant ERR_REPUTATION_TOO_LOW (err u11))
(define-constant ERR_ENGAGEMENT_REQUEST_NOT_FOUND (err u12))
(define-constant ERR_CONTENT_ALREADY_EXISTS (err u13))
(define-constant ERR_DEADLINE_PASSED (err u14))
(define-constant ERR_INSUFFICIENT_BALANCE (err u15))

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var content-id-nonce uint u0)
(define-data-var engagement-request-nonce uint u0)
(define-data-var minimum-influence uint u1000)
(define-data-var content-decay-rate uint u5)
(define-data-var base-reputation uint u100)

;; Data Maps
(define-map creative-content
    uint
    {
        name: (string-ascii 64),
        category: (string-ascii 32),
        decay-rate: uint,
        engagement-threshold: uint,
        is-active: bool,
        created-at: uint
    }
)

(define-map creator-dna-proofs
    {creator: principal, content-id: uint}
    {
        commitment-hash: (buff 32),
        merkle-root: (buff 32),
        virality-score: uint,
        last-curated: uint,
        curator: principal,
        influence-amount: uint,
        dna-valid-until: uint
    }
)

(define-map curator-profiles
    principal
    {
        reputation-score: uint,
        total-curations: uint,
        successful-curations: uint,
        total-influenced: uint,
        is-approved: bool
    }
)

(define-map engagement-requests
    uint
    {
        requester: principal,
        content-requirements: (list 10 uint),
        virality-threshold: uint,
        reputation-threshold: uint,
        deadline: uint,
        is-active: bool,
        reward-amount: uint
    }
)

(define-map content-collaborations
    uint
    {
        parent-content: uint,
        required-subcontent: (list 5 uint),
        collab-logic: (string-ascii 32)
    }
)

(define-map creator-reputation
    principal
    {
        base-score: uint,
        curation-bonus: uint,
        influence-penalties: uint,
        last-updated: uint
    }
)

(define-map temporal-content-weights
    {content-id: uint, time-period: uint}
    {
        weight-multiplier: uint,
        decay-applied: bool
    }
)

;; Private Functions
(define-private (verify-merkle-path (proof-element (buff 32)) (current-hash (buff 32)))
    (keccak256 (concat current-hash proof-element))
)

(define-private (calculate-reputation (creator principal))
    (match (map-get? creator-reputation creator)
        reputation
        (+ (get base-score reputation) 
           (- (get curation-bonus reputation) (get influence-penalties reputation)))
        (var-get base-reputation)
    )
)

(define-private (is-content-expired (dna-proof {commitment-hash: (buff 32), merkle-root: (buff 32), virality-score: uint, last-curated: uint, curator: principal, influence-amount: uint, dna-valid-until: uint}))
    (> block-height (get dna-valid-until dna-proof))
)

;; Owner Functions
(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (ok (var-set contract-owner new-owner))
    )
)

(define-public (set-minimum-influence (new-minimum uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (asserts! (> new-minimum u0) ERR_INVALID_ENGAGEMENT)
        (ok (var-set minimum-influence new-minimum))
    )
)

(define-public (approve-curator (curator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (match (map-get? curator-profiles curator)
            existing-profile (ok (map-set curator-profiles curator 
                (merge existing-profile {is-approved: true})))
            (ok (map-set curator-profiles curator {
                reputation-score: (var-get base-reputation),
                total-curations: u0,
                successful-curations: u0,
                total-influenced: u0,
                is-approved: true
            }))
        )
    )
)

(define-public (revoke-curator (curator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (match (map-get? curator-profiles curator)
            existing-profile (ok (map-set curator-profiles curator 
                (merge existing-profile {is-approved: false})))
            ERR_CURATOR_NOT_FOUND
        )
    )
)

;; Public Functions
(define-public (register-content (name (string-ascii 64)) (category (string-ascii 32)) (threshold uint))
    (let ((content-id (+ (var-get content-id-nonce) u1)))
        (asserts! (> threshold u0) ERR_INVALID_ENGAGEMENT)
        (asserts! (< threshold u101) ERR_INVALID_ENGAGEMENT)
        (asserts! (> (len name) u0) ERR_INVALID_CONTENT)
        
        (map-set creative-content content-id {
            name: name,
            category: category,
            decay-rate: (var-get content-decay-rate),
            engagement-threshold: threshold,
            is-active: true,
            created-at: block-height
        })
        (var-set content-id-nonce content-id)
        (ok content-id)
    )
)

(define-public (submit-dna-proof 
    (content-id uint) 
    (commitment (buff 32)) 
    (merkle-root (buff 32))
    (virality uint)
    (influence-amount uint))
    (let (
        (curator-profile (unwrap! (map-get? curator-profiles tx-sender) ERR_CURATOR_NOT_FOUND))
        (content-info (unwrap! (map-get? creative-content content-id) ERR_INVALID_CONTENT))
    )
        (asserts! (get is-approved curator-profile) ERR_UNAUTHORIZED)
        (asserts! (>= influence-amount (var-get minimum-influence)) ERR_INSUFFICIENT_INFLUENCE)
        (asserts! (and (>= virality u1) (<= virality u100)) ERR_INVALID_ENGAGEMENT)
        (asserts! (get is-active content-info) ERR_INVALID_CONTENT)
        (asserts! (not (is-eq commitment 0x00)) ERR_INVALID_COMMITMENT)
        
        (asserts! (is-none (map-get? creator-dna-proofs {creator: tx-sender, content-id: content-id})) 
                  ERR_DUPLICATE_CURATION)
        
        (try! (stx-transfer? influence-amount tx-sender (as-contract tx-sender)))
        
        (map-set creator-dna-proofs 
            {creator: tx-sender, content-id: content-id}
            {
                commitment-hash: commitment,
                merkle-root: merkle-root,
                virality-score: virality,
                last-curated: block-height,
                curator: tx-sender,
                influence-amount: influence-amount,
                dna-valid-until: (+ block-height u52560)
            }
        )
        
        (map-set curator-profiles tx-sender 
            (merge curator-profile {
                total-curations: (+ (get total-curations curator-profile) u1),
                total-influenced: (+ (get total-influenced curator-profile) influence-amount)
            })
        )
        
        (ok true)
    )
)

(define-public (create-engagement-request 
    (content-requirements (list 10 uint))
    (virality-threshold uint)
    (reputation-threshold uint)
    (deadline uint)
    (reward-amount uint))
    (let ((request-id (+ (var-get engagement-request-nonce) u1)))
        (asserts! (> (len content-requirements) u0) ERR_INVALID_CONTENT)
        (asserts! (and (>= virality-threshold u1) (<= virality-threshold u100)) ERR_INVALID_ENGAGEMENT)
        (asserts! (> deadline block-height) ERR_DEADLINE_PASSED)
        (asserts! (> reward-amount u0) ERR_INVALID_ENGAGEMENT)
        
        (try! (stx-transfer? reward-amount tx-sender (as-contract tx-sender)))
        
        (map-set engagement-requests request-id {
            requester: tx-sender,
            content-requirements: content-requirements,
            virality-threshold: virality-threshold,
            reputation-threshold: reputation-threshold,
            deadline: deadline,
            is-active: true,
            reward-amount: reward-amount
        })
        (var-set engagement-request-nonce request-id)
        (ok request-id)
    )
)

(define-public (verify-dna-proof 
    (creator principal)
    (content-id uint)
    (merkle-proof (list 10 (buff 32)))
    (leaf-data (buff 32)))
    (let (
        (dna-proof (unwrap! (map-get? creator-dna-proofs {creator: creator, content-id: content-id}) ERR_INVALID_DNA))
        (curator-profile (unwrap! (map-get? curator-profiles tx-sender) ERR_CURATOR_NOT_FOUND))
        (calculated-root (fold verify-merkle-path merkle-proof leaf-data))
    )
        (asserts! (get is-approved curator-profile) ERR_UNAUTHORIZED)
        (asserts! (< block-height (get dna-valid-until dna-proof)) ERR_CONTENT_EXPIRED)
        (asserts! (is-eq calculated-root (get merkle-root dna-proof)) ERR_INVALID_MERKLE_PROOF)
        
        (map-set curator-profiles tx-sender 
            (merge curator-profile {
                successful-curations: (+ (get successful-curations curator-profile) u1)
            })
        )
        
        (match (map-get? creator-reputation creator)
            existing-rep (map-set creator-reputation creator 
                (merge existing-rep {
                    curation-bonus: (+ (get curation-bonus existing-rep) u10),
                    last-updated: block-height
                }))
            (map-set creator-reputation creator {
                base-score: (var-get base-reputation),
                curation-bonus: u10,
                influence-penalties: u0,
                last-updated: block-height
            })
        )
        
        (ok true)
    )
)

(define-public (update-content-temporal-weight (content-id uint) (time-period uint) (weight uint))
    (begin
        (asserts! (is-some (map-get? creative-content content-id)) ERR_INVALID_CONTENT)
        (asserts! (and (>= weight u1) (<= weight u200)) ERR_INVALID_ENGAGEMENT)
        
        (map-set temporal-content-weights 
            {content-id: content-id, time-period: time-period}
            {weight-multiplier: weight, decay-applied: false}
        )
        (ok true)
    )
)

(define-public (compose-content 
    (parent-content uint)
    (subcontent (list 5 uint))
    (logic (string-ascii 32)))
    (begin
        (asserts! (is-some (map-get? creative-content parent-content)) ERR_INVALID_CONTENT)
        (asserts! (> (len subcontent) u0) ERR_INVALID_CONTENT)
        (asserts! (or (is-eq logic "AND") (or (is-eq logic "OR") (is-eq logic "THRESHOLD"))) ERR_INVALID_CONTENT)
        
        (map-set content-collaborations parent-content {
            parent-content: parent-content,
            required-subcontent: subcontent,
            collab-logic: logic
        })
        (ok true)
    )
)

(define-public (withdraw-influence (content-id uint))
    (let (
        (dna-proof (unwrap! (map-get? creator-dna-proofs {creator: tx-sender, content-id: content-id}) ERR_INVALID_DNA))
    )
        (asserts! (> block-height (get dna-valid-until dna-proof)) ERR_CONTENT_EXPIRED)
        
        (try! (as-contract (stx-transfer? (get influence-amount dna-proof) tx-sender tx-sender)))
        
        (map-delete creator-dna-proofs {creator: tx-sender, content-id: content-id})
        (ok (get influence-amount dna-proof))
    )
)

(define-public (deactivate-content (content-id uint))
    (let (
        (content-info (unwrap! (map-get? creative-content content-id) ERR_INVALID_CONTENT))
    )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        
        (map-set creative-content content-id 
            (merge content-info {is-active: false}))
        (ok true)
    )
)

(define-public (fulfill-engagement-request (request-id uint) (content-proofs (list 10 uint)))
    (let (
        (request (unwrap! (map-get? engagement-requests request-id) ERR_ENGAGEMENT_REQUEST_NOT_FOUND))
        (creator-rep (calculate-reputation tx-sender))
    )
        (asserts! (get is-active request) ERR_ENGAGEMENT_REQUEST_NOT_FOUND)
        (asserts! (< block-height (get deadline request)) ERR_DEADLINE_PASSED)
        (asserts! (>= creator-rep (get reputation-threshold request)) ERR_REPUTATION_TOO_LOW)
        (asserts! (is-eq (len content-proofs) (len (get content-requirements request))) ERR_INVALID_CONTENT)
        
        (map-set engagement-requests request-id 
            (merge request {is-active: false}))
        
        (try! (as-contract (stx-transfer? (get reward-amount request) tx-sender (get requester request))))
        
        (match (map-get? creator-reputation tx-sender)
            existing-rep (map-set creator-reputation tx-sender 
                (merge existing-rep {
                    curation-bonus: (+ (get curation-bonus existing-rep) u20),
                    last-updated: block-height
                }))
            (map-set creator-reputation tx-sender {
                base-score: (var-get base-reputation),
                curation-bonus: u20,
                influence-penalties: u0,
                last-updated: block-height
            })
        )
        
        (ok true)
    )
)

(define-public (apply-content-decay (content-id uint))
    (let (
        (content-info (unwrap! (map-get? creative-content content-id) ERR_INVALID_CONTENT))
        (time-weight (map-get? temporal-content-weights {content-id: content-id, time-period: block-height}))
    )
        (asserts! (get is-active content-info) ERR_INVALID_CONTENT)
        
        (match time-weight
            weight-info 
            (if (not (get decay-applied weight-info))
                (begin
                    (map-set temporal-content-weights 
                        {content-id: content-id, time-period: block-height}
                        (merge weight-info {decay-applied: true}))
                    (ok true))
                (ok false))
            (ok false)
        )
    )
)

;; Read-Only Functions
(define-read-only (get-content-info (content-id uint))
    (map-get? creative-content content-id)
)

(define-read-only (get-creator-dna-proof (creator principal) (content-id uint))
    (map-get? creator-dna-proofs {creator: creator, content-id: content-id})
)

(define-read-only (get-curator-profile (curator principal))
    (map-get? curator-profiles curator)
)

(define-read-only (get-engagement-request (request-id uint))
    (map-get? engagement-requests request-id)
)

(define-read-only (get-content-collaboration (content-id uint))
    (map-get? content-collaborations content-id)
)

(define-read-only (get-creator-reputation (creator principal))
    (calculate-reputation creator)
)

(define-read-only (get-temporal-weight (content-id uint) (time-period uint))
    (map-get? temporal-content-weights {content-id: content-id, time-period: time-period})
)

(define-read-only (get-contract-info)
    {
        owner: (var-get contract-owner),
        content-count: (var-get content-id-nonce),
        engagement-request-count: (var-get engagement-request-nonce),
        minimum-influence: (var-get minimum-influence),
        decay-rate: (var-get content-decay-rate),
        base-reputation: (var-get base-reputation)
    }
)

(define-read-only (is-curator-approved (curator principal))
    (match (map-get? curator-profiles curator)
        profile (get is-approved profile)
        false
    )
)

(define-read-only (get-content-virality (creator principal) (content-id uint))
    (match (map-get? creator-dna-proofs {creator: creator, content-id: content-id})
        proof (some (get virality-score proof))
        none
    )
)