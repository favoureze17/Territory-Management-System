;; WorldForge - Virtual world economics and territory management system
;; Smart Contract for Stacks Blockchain

;; Contract constants
(define-constant contract-architect tx-sender)
(define-constant err-architect-only (err u400))
(define-constant err-insufficient-resources (err u401))
(define-constant err-territory-not-found (err u402))
(define-constant err-guild-not-exists (err u403))
(define-constant err-settlement-conflict (err u404))
(define-constant err-trade-route-forbidden (err u405))
(define-constant err-world-law-violation (err u406))
(define-constant err-economy-locked (err u407))
(define-constant err-invalid-input (err u408))
(define-constant err-invalid-principal (err u409))

;; Data variables
(define-data-var territory-registry-counter uint u0)
(define-data-var guild-hierarchy-counter uint u0)
(define-data-var trade-window uint u144) ;; ~24 hours in blocks
(define-data-var world-decree-counter uint u0)

;; Core data structures
(define-map territory-registry
  { territory-id: uint }
  {
    territory-name: (string-ascii 50),
    resource-domain: (string-ascii 100),
    economic-value: uint,
    founded-by: principal,
    founding-block: uint,
    is-tradeable: bool,
    abandonment-block: (optional uint),
    territory-lore: (string-ascii 200)
  }
)

(define-map guild-hierarchy
  { guild-id: uint }
  {
    guild-name: (string-ascii 50),
    influence-level: uint,
    parent-guild: (optional uint),
    territory-claims: (list 50 uint),
    guild-master: principal,
    max-members: uint,
    current-members: uint,
    trade-enabled: bool,
    guild-status: bool
  }
)

(define-map settlement-assignments
  { settler: principal, guild-id: uint }
  {
    recruited-by: principal,
    settlement-block: uint,
    exile-block: (optional uint),
    loyalty-depth: uint,
    settlement-chronicle: (string-ascii 150),
    citizenship-active: bool,
    last-contribution: uint
  }
)

(define-map trade-route-registry
  { merchant: principal, client: principal, territory-id: uint }
  {
    trade-established: uint,
    route-expires: uint,
    trade-terms: (string-ascii 100),
    embargo-authority: principal,
    route-active: bool
  }
)

(define-map economy-controls
  { realm-id: (string-ascii 100) }
  {
    controlling-authority: principal,
    control-duration: uint,
    control-reason: (string-ascii 150),
    controlled-since: uint,
    liberation-conditions: (string-ascii 200)
  }
)

(define-map world-decrees
  { decree-id: uint }
  {
    decree-issuer: principal,
    decree-type: (string-ascii 30),
    target-guild: (optional uint),
    target-territory: (optional uint),
    decree-content: (string-ascii 300),
    support-count: uint,
    resistance-count: uint,
    decree-expiry: uint,
    enforcement-status: bool
  }
)

;; Input validation functions
(define-private (is-valid-string (input (string-ascii 300)))
  (> (len input) u0)
)

(define-private (is-valid-uint (input uint))
  (<= input u1000000) ;; Reasonable upper bound
)

(define-private (is-valid-principal (input principal))
  (not (is-eq input 'SP000000000000000000002Q6VF78)) ;; Not burn address
)

(define-private (is-valid-duration (duration uint))
  (and (> duration u0) (<= duration u1000000)) ;; Between 1 and 1M blocks
)

;; Private utility functions
(define-private (increment-territory-counter)
  (let ((current-counter (var-get territory-registry-counter)))
    (var-set territory-registry-counter (+ current-counter u1))
    (+ current-counter u1)
  )
)

(define-private (increment-guild-counter)
  (let ((current-counter (var-get guild-hierarchy-counter)))
    (var-set guild-hierarchy-counter (+ current-counter u1))
    (+ current-counter u1)
  )
)

(define-private (increment-decree-counter)
  (let ((current-counter (var-get world-decree-counter)))
    (var-set world-decree-counter (+ current-counter u1))
    (+ current-counter u1)
  )
)

(define-private (has-territory-rights (settler principal) (territory-id uint))
  (let ((settlement-exists (is-some (map-get? settlement-assignments { settler: settler, guild-id: u1 }))))
    ;; Simplified check - in production would iterate through settler's guilds
    settlement-exists
  )
)

(define-private (validate-influence-level (guild-id uint) (required-level uint))
  (match (map-get? guild-hierarchy { guild-id: guild-id })
    guild-data (>= (get influence-level guild-data) required-level)
    false
  )
)

(define-private (is-guild-master (settler principal) (guild-id uint))
  (match (map-get? guild-hierarchy { guild-id: guild-id })
    guild-data (is-eq settler (get guild-master guild-data))
    false
  )
)

(define-private (is-territory-abandoned (territory-id uint))
  (match (map-get? territory-registry { territory-id: territory-id })
    territory-data
    (match (get abandonment-block territory-data)
      abandon-block (> block-height abandon-block)
      false
    )
    true
  )
)

;; Core world management functions

;; Create a new territory with specified parameters
(define-public (forge-territory 
  (territory-name (string-ascii 50))
  (resource-domain (string-ascii 100))
  (economic-value uint)
  (is-tradeable bool)
  (abandonment-block (optional uint))
  (territory-lore (string-ascii 200)))
  (begin
    ;; Input validation
    (asserts! (is-valid-string territory-name) err-invalid-input)
    (asserts! (is-valid-string resource-domain) err-invalid-input)
    (asserts! (is-valid-uint economic-value) err-invalid-input)
    (asserts! (is-valid-string territory-lore) err-invalid-input)
    
    ;; Validate and prepare abandonment block
    (let ((validated-abandonment-block
            (match abandonment-block
              abandon-val 
                (begin
                  (asserts! (> abandon-val block-height) err-invalid-input)
                  (some abandon-val)
                )
              none
            )))
      
      (let ((territory-id (increment-territory-counter)))
        (map-set territory-registry
          { territory-id: territory-id }
          {
            territory-name: territory-name,
            resource-domain: resource-domain,
            economic-value: economic-value,
            founded-by: tx-sender,
            founding-block: block-height,
            is-tradeable: is-tradeable,
            abandonment-block: validated-abandonment-block,
            territory-lore: territory-lore
          }
        )
              (ok territory-id)
      )
    )
  )
)

;; Establish a new guild in the hierarchy
(define-public (establish-guild
  (guild-name (string-ascii 50))
  (influence-level uint)
  (parent-guild (optional uint))
  (max-members uint)
  (trade-enabled bool))
  (begin
    ;; Input validation
    (asserts! (is-valid-string guild-name) err-invalid-input)
    (asserts! (is-valid-uint influence-level) err-invalid-input)
    (asserts! (and (> max-members u0) (<= max-members u1000)) err-invalid-input)
    
    ;; Validate and prepare parent guild
    (let ((validated-parent-guild
            (match parent-guild
              parent-id 
                (begin
                  (asserts! (is-some (map-get? guild-hierarchy { guild-id: parent-id })) err-guild-not-exists)
                  (some parent-id)
                )
              none
            )))
      
      (let ((guild-id (increment-guild-counter)))
        (map-set guild-hierarchy
          { guild-id: guild-id }
          {
            guild-name: guild-name,
            influence-level: influence-level,
            parent-guild: validated-parent-guild,
            territory-claims: (list),
            guild-master: tx-sender,
            max-members: max-members,
            current-members: u0,
            trade-enabled: trade-enabled,
            guild-status: true
          }
        )
              (ok guild-id)
      )
    )
  )
)

;; Grant territory claim to a guild
(define-public (grant-guild-territory-claim 
  (guild-id uint)
  (territory-id uint))
  (begin
    ;; Input validation
    (asserts! (is-valid-uint guild-id) err-invalid-input)
    (asserts! (is-valid-uint territory-id) err-invalid-input)
    
    (let ((guild-data (unwrap! (map-get? guild-hierarchy { guild-id: guild-id }) err-guild-not-exists))
          (territory-data (unwrap! (map-get? territory-registry { territory-id: territory-id }) err-territory-not-found)))
      (asserts! (or (is-eq tx-sender contract-architect) 
                    (is-guild-master tx-sender guild-id)) err-insufficient-resources)
      
      (let ((updated-claims (unwrap-panic (as-max-len? 
            (append (get territory-claims guild-data) territory-id) u50))))
        (map-set guild-hierarchy
          { guild-id: guild-id }
          (merge guild-data { territory-claims: updated-claims })
        )
        (ok true)
      )
    )
  )
)

;; Settle participant in a guild
(define-public (settle-in-guild
  (settler principal)
  (guild-id uint)
  (exile-block (optional uint))
  (settlement-chronicle (string-ascii 150)))
  (begin
    ;; Input validation
    (asserts! (is-valid-principal settler) err-invalid-principal)
    (asserts! (is-valid-uint guild-id) err-invalid-input)
    (asserts! (is-valid-string settlement-chronicle) err-invalid-input)
    
    ;; Validate exile block if provided and process settlement
    (let ((safe-exile-block 
            (if (is-some exile-block)
              (let ((exile-val (unwrap-panic exile-block)))
                (begin
                  (asserts! (> exile-val block-height) err-invalid-input)
                  exile-block
                )
              )
              none
            ))
          (guild-data (unwrap! (map-get? guild-hierarchy { guild-id: guild-id }) err-guild-not-exists)))
      (asserts! (or (is-eq tx-sender contract-architect) 
                    (is-guild-master tx-sender guild-id)) err-insufficient-resources)
      (asserts! (< (get current-members guild-data) (get max-members guild-data)) err-settlement-conflict)
      
      (map-set settlement-assignments
        { settler: settler, guild-id: guild-id }
        {
          recruited-by: tx-sender,
          settlement-block: block-height,
          exile-block: safe-exile-block,
          loyalty-depth: u0,
          settlement-chronicle: settlement-chronicle,
          citizenship-active: true,
          last-contribution: block-height
        }
      )
      (map-set guild-hierarchy
        { guild-id: guild-id }
        (merge guild-data { current-members: (+ (get current-members guild-data) u1) })
      )
      (ok true)
    )
  )
)

;; Establish trade route between merchants
(define-public (establish-trade-route
  (client principal)
  (territory-id uint)
  (route-expires uint)
  (trade-terms (string-ascii 100)))
  (begin
    ;; Input validation
    (asserts! (is-valid-principal client) err-invalid-principal)
    (asserts! (is-valid-uint territory-id) err-invalid-input)
    (asserts! (> route-expires block-height) err-invalid-input)
    (asserts! (is-valid-string trade-terms) err-invalid-input)
    
    (let ((territory-data (unwrap! (map-get? territory-registry { territory-id: territory-id }) err-territory-not-found)))
      (asserts! (and (get is-tradeable territory-data)
                     (has-territory-rights tx-sender territory-id)
                     (not (is-territory-abandoned territory-id))) err-trade-route-forbidden)
      
      (map-set trade-route-registry
        { merchant: tx-sender, client: client, territory-id: territory-id }
        {
          trade-established: block-height,
          route-expires: route-expires,
          trade-terms: trade-terms,
          embargo-authority: tx-sender,
          route-active: true
        }
      )
      (ok true)
    )
  )
)

;; Exile settler from guild
(define-public (exile-from-guild
  (settler principal)
  (guild-id uint))
  (begin
    ;; Input validation
    (asserts! (is-valid-principal settler) err-invalid-principal)
    (asserts! (is-valid-uint guild-id) err-invalid-input)
    
    (let ((guild-data (unwrap! (map-get? guild-hierarchy { guild-id: guild-id }) err-guild-not-exists))
          (settlement-data (unwrap! (map-get? settlement-assignments { settler: settler, guild-id: guild-id }) err-territory-not-found)))
      (asserts! (or (is-eq tx-sender contract-architect) 
                    (is-guild-master tx-sender guild-id)
                    (is-eq tx-sender (get recruited-by settlement-data))) err-insufficient-resources)
      
      (map-set settlement-assignments
        { settler: settler, guild-id: guild-id }
        (merge settlement-data { citizenship-active: false })
      )
      (map-set guild-hierarchy
        { guild-id: guild-id }
        (merge guild-data { current-members: (- (get current-members guild-data) u1) })
      )
      (ok true)
    )
  )
)

;; Embargo trade route
(define-public (embargo-trade-route
  (client principal)
  (territory-id uint))
  (begin
    ;; Input validation
    (asserts! (is-valid-principal client) err-invalid-principal)
    (asserts! (is-valid-uint territory-id) err-invalid-input)
    
    (let ((route-data (unwrap! (map-get? trade-route-registry 
      { merchant: tx-sender, client: client, territory-id: territory-id }) err-territory-not-found)))
      (asserts! (is-eq tx-sender (get embargo-authority route-data)) err-insufficient-resources)
      
      (map-set trade-route-registry
        { merchant: tx-sender, client: client, territory-id: territory-id }
        (merge route-data { route-active: false })
      )
      (ok true)
    )
  )
)

;; Lock economic activity temporarily
(define-public (engage-economy-control
  (realm-id (string-ascii 100))
  (control-duration uint)
  (control-reason (string-ascii 150))
  (liberation-conditions (string-ascii 200)))
  (begin
    ;; Input validation
    (asserts! (is-eq tx-sender contract-architect) err-architect-only)
    (asserts! (is-valid-string realm-id) err-invalid-input)
    (asserts! (is-valid-duration control-duration) err-invalid-input)
    (asserts! (is-valid-string control-reason) err-invalid-input)
    (asserts! (is-valid-string liberation-conditions) err-invalid-input)
    
    (map-set economy-controls
      { realm-id: realm-id }
      {
        controlling-authority: tx-sender,
        control-duration: control-duration,
        control-reason: control-reason,
        controlled-since: block-height,
        liberation-conditions: liberation-conditions
      }
    )
    (ok true)
  )
)

;; Issue world decree
(define-public (issue-world-decree
  (decree-type (string-ascii 30))
  (target-guild (optional uint))
  (target-territory (optional uint))
  (decree-content (string-ascii 300))
  (decree-duration uint))
  (begin
    ;; Input validation
    (asserts! (is-valid-string decree-type) err-invalid-input)
    (asserts! (is-valid-string decree-content) err-invalid-input)
    (asserts! (is-valid-duration decree-duration) err-invalid-input)
    
    ;; Validate and prepare target guild and territory
    (let ((validated-target-guild
            (match target-guild
              guild-id 
                (begin
                  (asserts! (is-some (map-get? guild-hierarchy { guild-id: guild-id })) err-guild-not-exists)
                  (some guild-id)
                )
              none
            ))
          (validated-target-territory
            (match target-territory
              territory-id 
                (begin
                  (asserts! (is-some (map-get? territory-registry { territory-id: territory-id })) err-territory-not-found)
                  (some territory-id)
                )
              none
            )))
      
      (let ((decree-id (increment-decree-counter)))
        (map-set world-decrees
          { decree-id: decree-id }
          {
            decree-issuer: tx-sender,
            decree-type: decree-type,
            target-guild: validated-target-guild,
            target-territory: validated-target-territory,
            decree-content: decree-content,
            support-count: u0,
            resistance-count: u0,
            decree-expiry: (+ block-height decree-duration),
            enforcement-status: false
          }
        )
              (ok decree-id)
      )
    )
  )
)

;; Update trade window
(define-public (configure-trade-window (new-window uint))
  (begin
    ;; Input validation
    (asserts! (is-eq tx-sender contract-architect) err-architect-only)
    (asserts! (and (> new-window u0) (<= new-window u10000)) err-invalid-input) ;; Reasonable bounds
    
    (var-set trade-window new-window)
    (ok true)
  )
)

;; Read-only functions for world verification

;; Check if settler has territory rights
(define-read-only (verify-territory-access (settler principal) (territory-id uint))
  (has-territory-rights settler territory-id)
)

;; Get territory details
(define-read-only (get-territory-details (territory-id uint))
  (map-get? territory-registry { territory-id: territory-id })
)

;; Get guild information
(define-read-only (get-guild-details (guild-id uint))
  (map-get? guild-hierarchy { guild-id: guild-id })
)

;; Get settler's settlement details
(define-read-only (get-settlement-details (settler principal) (guild-id uint))
  (map-get? settlement-assignments { settler: settler, guild-id: guild-id })
)

;; Check trade route status
(define-read-only (get-trade-route-status (merchant principal) (client principal) (territory-id uint))
  (map-get? trade-route-registry { merchant: merchant, client: client, territory-id: territory-id })
)

;; Get economy control status
(define-read-only (get-economy-control-status (realm-id (string-ascii 100)))
  (map-get? economy-controls { realm-id: realm-id })
)

;; Get world decree details
(define-read-only (get-decree-details (decree-id uint))
  (map-get? world-decrees { decree-id: decree-id })
)

;; Get current trade window
(define-read-only (get-trade-window)
  (var-get trade-window)
)

;; Get total territories count
(define-read-only (get-total-territories)
  (var-get territory-registry-counter)
)

;; Get total guilds count
(define-read-only (get-total-guilds)
  (var-get guild-hierarchy-counter)
)

;; Get total decrees count
(define-read-only (get-total-decrees)
  (var-get world-decree-counter)
)

;; Validate guild influence access
(define-read-only (validate-influence-access (guild-id uint) (required-level uint))
  (validate-influence-level guild-id required-level)
)

;; Check if settler is guild master
(define-read-only (check-guild-master (settler principal) (guild-id uint))
  (is-guild-master settler guild-id)
)

;; Check if territory is abandoned
(define-read-only (check-territory-abandonment (territory-id uint))
  (is-territory-abandoned territory-id)
)