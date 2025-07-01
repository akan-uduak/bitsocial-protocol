;; BitSocial Protocol
;; 
;; A revolutionary Bitcoin-secured social infrastructure that transforms how creators 
;; monetize content and build communities in the decentralized economy.
;; 
;; BitSocial harnesses the security of Bitcoin through Stacks Layer 2 to deliver 
;; censorship-resistant social networking with built-in economic incentives. 
;; Creators earn directly from their audience through microtips, build tokenized 
;; communities with governance rights, and maintain sovereign control over their 
;; digital identity - all while benefiting from Bitcoin's unmatched security guarantees.
;;
;; Core Value Propositions:
;; - Sovereign Identity: Own your profile, data, and social graph forever
;; - Creator Economy: Direct monetization through STX microtips with no intermediaries  
;; - Community Governance: Launch tokenized communities with built-in voting mechanisms
;; - Bitcoin Security: All interactions inherit Bitcoin's immutable settlement layer
;; - Composable Infrastructure: Open protocol enabling infinite social app possibilities

;; CONSTANTS & ERROR CODES

(define-constant CONTRACT_OWNER tx-sender)

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_NOT_FOUND (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_INVALID_PARAMS (err u105))
(define-constant ERR_PROFILE_NOT_FOUND (err u106))
(define-constant ERR_CONTENT_NOT_FOUND (err u107))
(define-constant ERR_ALREADY_TIPPED (err u108))
(define-constant ERR_SELF_TIP (err u109))
(define-constant ERR_COMMUNITY_EXISTS (err u110))
(define-constant ERR_INVALID_URL (err u111))
(define-constant ERR_INVALID_MESSAGE (err u112))

;; Protocol configuration constants
(define-constant PROTOCOL_FEE_BPS u250)           ;; 2.5% protocol sustainability fee
(define-constant MIN_TIP_AMOUNT u1000)            ;; Minimum tip: 1000 microSTX
(define-constant MAX_HANDLE_LENGTH u32)           ;; Username character limit
(define-constant MAX_BIO_LENGTH u256)             ;; Profile bio character limit
(define-constant MAX_CONTENT_LENGTH u1024)        ;; Post content character limit
(define-constant MAX_URL_LENGTH u256)             ;; Media URL character limit
(define-constant MAX_MESSAGE_LENGTH u256)         ;; Tip message character limit
(define-constant INITIAL_REPUTATION u100)         ;; Starting reputation score

;; DATA VARIABLES

(define-data-var protocol-fee-recipient principal CONTRACT_OWNER)
(define-data-var next-profile-id uint u1)
(define-data-var next-content-id uint u1)
(define-data-var next-community-id uint u1)
(define-data-var protocol-paused bool false)

;; DATA MAPS - CORE PROTOCOL STATE

;; User identity profiles with comprehensive social metrics
(define-map user-profiles
  { profile-id: uint }
  {
    owner: principal,
    handle: (string-ascii 32),
    bio: (string-utf8 256),
    avatar-url: (optional (string-ascii 256)),
    reputation-score: uint,
    total-tips-received: uint,
    total-tips-sent: uint,
    content-count: uint,
    follower-count: uint,
    following-count: uint,
    created-at: uint,
    verified: bool
  }
)

;; Unique handle registry for username resolution
(define-map handle-to-profile (string-ascii 32) uint)

;; Principal-to-profile mapping for identity lookup
(define-map principal-to-profile principal uint)

;; Content posts with monetization and engagement tracking
(define-map content-posts
  { content-id: uint }
  {
    author-id: uint,
    content-text: (string-utf8 1024),
    content-type: (string-ascii 5),              ;; "text", "image", "video", "audio", "link"
    media-url: (optional (string-ascii 256)),
    tip-count: uint,
    total-tips: uint,
    engagement-score: uint,
    created-at: uint,
    community-id: (optional uint)
  }
)

;; Tip records for creator monetization transparency
(define-map content-tips
  { content-id: uint, tipper: principal }
  {
    amount: uint,
    message: (optional (string-utf8 256)),
    tipped-at: uint
  }
)

;; Social graph connections (follower/following relationships)
(define-map social-connections
  { follower-id: uint, following-id: uint }
  { connected-at: uint }
)

;; Tokenized communities with governance capabilities
(define-map communities
  { community-id: uint }
  {
    name: (string-ascii 64),
    description: (string-utf8 256),
    creator-id: uint,
    token-symbol: (string-ascii 8),
    total-supply: uint,
    member-count: uint,
    created-at: uint,
    governance-threshold: uint
  }
)

;; Community membership with token holdings and permissions
(define-map community-members
  { community-id: uint, member-id: uint }
  {
    token-balance: uint,
    joined-at: uint,
    is-moderator: bool
  }
)

;; Time-based engagement tracking for reputation calculation
(define-map user-engagement
  { profile-id: uint, period: uint }             ;; period = block-height / 2016 (weekly epochs)
  {
    tips-received: uint,
    tips-sent: uint,
    content-posted: uint,
    engagement-score: uint
  }
)

;; PRIVATE HELPER FUNCTIONS

(define-private (is-valid-handle (handle (string-ascii 32)))
  (and 
    (> (len handle) u0)
    (<= (len handle) MAX_HANDLE_LENGTH)
    (is-none (map-get? handle-to-profile handle))
  )
)

(define-private (is-valid-url (url (string-ascii 256)))
  (and
    (> (len url) u0)
    (<= (len url) MAX_URL_LENGTH)
    ;; Basic URL validation - must start with http:// or https://
    (or
      (is-eq (unwrap-panic (slice? url u0 u7)) "http://")
      (is-eq (unwrap-panic (slice? url u0 u8)) "https://")
    )
  )
)

(define-private (is-valid-optional-url (url (optional (string-ascii 256))))
  (match url
    some-url (is-valid-url some-url)
    true ;; None is always valid
  )
)

(define-private (is-valid-message (message (optional (string-utf8 256))))
  (match message
    some-msg (<= (len some-msg) MAX_MESSAGE_LENGTH)
    true ;; None is always valid
  )
)

(define-private (is-valid-content-type (content-type (string-ascii 5)))
  (let ((valid-types (list "text" "image" "video" "audio" "link")))
    (is-some (index-of valid-types content-type))
  )
)

(define-private (calculate-protocol-fee (amount uint))
  (/ (* amount PROTOCOL_FEE_BPS) u10000)
)

(define-private (get-current-period)
  (/ stacks-block-height u2016) ;; Weekly engagement periods
)

(define-private (update-reputation (profile-id uint) (points uint))
  (let ((profile (unwrap! (map-get? user-profiles { profile-id: profile-id }) false)))
    (map-set user-profiles
      { profile-id: profile-id }
      (merge profile { reputation-score: (+ (get reputation-score profile) points) })
    )
    true
  )
)