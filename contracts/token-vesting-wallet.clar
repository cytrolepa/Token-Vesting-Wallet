(define-constant ERR_UNAUTHORIZED (err u1))
(define-constant ERR_INVALID_AMOUNT (err u2))
(define-constant ERR_INVALID_DURATION (err u3))
(define-constant ERR_SCHEDULE_NOT_FOUND (err u4))
(define-constant ERR_ALREADY_CLAIMED (err u5))
(define-constant ERR_NOTHING_TO_CLAIM (err u6))
(define-constant ERR_INSUFFICIENT_BALANCE (err u7))
(define-constant ERR_INVALID_BENEFICIARY (err u8))
(define-constant ERR_SCHEDULE_ALREADY_EXISTS (err u9))
(define-constant ERR_ZERO_AMOUNT (err u10))
(define-constant ERR_TEMPLATE_NOT_FOUND (err u11))
(define-constant ERR_TEMPLATE_ALREADY_EXISTS (err u12))
(define-constant ERR_INVALID_TEMPLATE_NAME (err u13))
(define-constant ERR_SCHEDULE_PAUSED (err u14))
(define-constant ERR_SCHEDULE_NOT_PAUSED (err u15))
(define-constant ERR_NEW_BENEFICIARY_EXISTS (err u16))
(define-constant ERR_SAME_BENEFICIARY (err u17))

(define-data-var owner principal tx-sender)
(define-data-var template-counter uint u0)
(define-data-var token-contract principal .token-vesting-wallet)

(define-map vesting-schedules
  { beneficiary: principal }
  {
    total-amount: uint,
    claimed-amount: uint,
    start-time: uint,
    cliff-time: uint,
    duration: uint,
    created-by: principal,
    active: bool,
    paused: bool,
    pause-time: uint
  }
)

(define-map vesting-balances
  { beneficiary: principal }
  { balance: uint }
)

(define-map claim-delegates
  { beneficiary: principal }
  { delegate: principal }
)

(define-map vesting-templates
  { template-id: uint }
  {
    name: (string-ascii 64),
    description: (string-ascii 256),
    cliff-duration: uint,
    vesting-duration: uint,
    created-by: principal,
    active: bool
  }
)

(define-map template-name-index
  { name: (string-ascii 64) }
  { template-id: uint }
)

(define-read-only (get-owner)
  (var-get owner)
)

(define-read-only (get-token-contract)
  (var-get token-contract)
)

(define-read-only (get-vesting-schedule (beneficiary principal))
  (map-get? vesting-schedules { beneficiary: beneficiary })
)

(define-read-only (get-vesting-balance (beneficiary principal))
  (default-to { balance: u0 } (map-get? vesting-balances { beneficiary: beneficiary }))
)

(define-read-only (get-template-counter)
  (var-get template-counter)
)

(define-read-only (get-vesting-template (template-id uint))
  (map-get? vesting-templates { template-id: template-id })
)

(define-read-only (get-template-by-name (name (string-ascii 64)))
  (match (map-get? template-name-index { name: name })
    some-index (get-vesting-template (get template-id some-index))
    none
  )
)

(define-read-only (get-template-id-by-name (name (string-ascii 64)))
  (map-get? template-name-index { name: name })
)

(define-read-only (calculate-vested-amount (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (start-time (get start-time schedule))
    (cliff-time (get cliff-time schedule))
    (duration (get duration schedule))
    (total-amount (get total-amount schedule))
    (is-paused (get paused schedule))
    (pause-time (get pause-time schedule))
    (effective-time (if is-paused pause-time current-time))
  )
    (if (< effective-time cliff-time)
      (ok u0)
      (if (>= effective-time (+ start-time duration))
        (ok total-amount)
        (let (
          (elapsed-time (- effective-time start-time))
          (vested-amount (/ (* total-amount elapsed-time) duration))
        )
          (ok vested-amount)
        )
      )
    )
  )
)

(define-read-only (get-claimable-amount (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
    (vested-amount (unwrap! (calculate-vested-amount beneficiary) (err u0)))
    (claimed-amount (get claimed-amount schedule))
  )
    (if (and (get active schedule) (> vested-amount claimed-amount))
      (ok (- vested-amount claimed-amount))
      (ok u0)
    )
  )
)

(define-read-only (get-remaining-time (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (end-time (+ (get start-time schedule) (get duration schedule)))
  )
    (if (>= current-time end-time)
      (ok u0)
      (ok (- end-time current-time))
    )
  )
)

(define-read-only (is-fully-vested (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) false))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (end-time (+ (get start-time schedule) (get duration schedule)))
  )
    (>= current-time end-time)
  )
)

(define-private (is-owner)
  (is-eq tx-sender (var-get owner))
)

(define-public (set-owner (new-owner principal))
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (var-set owner new-owner)
    (ok true)
  )
)

(define-public (set-token-contract (new-token-contract principal))
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (var-set token-contract new-token-contract)
    (ok true)
  )
)

(define-public (create-vesting-schedule 
  (beneficiary principal)
  (total-amount uint)
  (start-time uint)
  (cliff-duration uint)
  (vesting-duration uint)
)
  (let (
    (cliff-time (+ start-time cliff-duration))
    (existing-schedule (get-vesting-schedule beneficiary))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (> total-amount u0) ERR_ZERO_AMOUNT)
    (asserts! (> vesting-duration u0) ERR_INVALID_DURATION)
    (asserts! (not (is-eq beneficiary tx-sender)) ERR_INVALID_BENEFICIARY)
    (asserts! (is-none existing-schedule) ERR_SCHEDULE_ALREADY_EXISTS)
    
    (map-set vesting-schedules
      { beneficiary: beneficiary }
      {
        total-amount: total-amount,
        claimed-amount: u0,
        start-time: start-time,
        cliff-time: cliff-time,
        duration: vesting-duration,
        created-by: tx-sender,
        active: true,
        paused: false,
        pause-time: u0
      }
    )
    
    (map-set vesting-balances
      { beneficiary: beneficiary }
      { balance: total-amount }
    )
    
    (ok true)
  )
)

(define-public (deposit-tokens (amount uint))
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (ok true)
  )
)

(define-public (claim-tokens)
  (let (
    (schedule (unwrap! (get-vesting-schedule tx-sender) ERR_SCHEDULE_NOT_FOUND))
    (claimable-amount (unwrap! (get-claimable-amount tx-sender) ERR_NOTHING_TO_CLAIM))
    (current-claimed (get claimed-amount schedule))
  )
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    (asserts! (not (get paused schedule)) ERR_SCHEDULE_PAUSED)
    (asserts! (> claimable-amount u0) ERR_NOTHING_TO_CLAIM)

    (try! (as-contract (stx-transfer? claimable-amount tx-sender tx-sender)))

    (map-set vesting-schedules
      { beneficiary: tx-sender }
      (merge schedule { claimed-amount: (+ current-claimed claimable-amount) })
    )

    (ok claimable-amount)
  )
)

(define-read-only (get-claim-delegate (beneficiary principal))
  (map-get? claim-delegates { beneficiary: beneficiary })
)

(define-public (set-claim-delegate (beneficiary principal) (delegate principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
  )
    (asserts! (or (is-eq tx-sender beneficiary) (is-owner)) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    (map-set claim-delegates { beneficiary: beneficiary } { delegate: delegate })
    (ok true)
  )
)

(define-public (clear-claim-delegate (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
  )
    (asserts! (or (is-eq tx-sender beneficiary) (is-owner)) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    (map-delete claim-delegates { beneficiary: beneficiary })
    (ok true)
  )
)

(define-public (claim-tokens-for (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
    (delegate-entry (default-to { delegate: beneficiary } (map-get? claim-delegates { beneficiary: beneficiary })))
    (authorized (or (is-eq tx-sender beneficiary) (is-eq tx-sender (get delegate delegate-entry))))
    (claimable-amount (unwrap! (get-claimable-amount beneficiary) ERR_NOTHING_TO_CLAIM))
    (current-claimed (get claimed-amount schedule))
  )
    (asserts! authorized ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    (asserts! (not (get paused schedule)) ERR_SCHEDULE_PAUSED)
    (asserts! (> claimable-amount u0) ERR_NOTHING_TO_CLAIM)

    (try! (as-contract (stx-transfer? claimable-amount tx-sender beneficiary)))

    (map-set vesting-schedules
      { beneficiary: beneficiary }
      (merge schedule { claimed-amount: (+ current-claimed claimable-amount) })
    )

    (ok claimable-amount)
  )
)

(define-public (revoke-vesting-schedule (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
    (vested-amount (unwrap! (calculate-vested-amount beneficiary) ERR_SCHEDULE_NOT_FOUND))
    (claimed-amount (get claimed-amount schedule))
    (remaining-claimable (if (> vested-amount claimed-amount) (- vested-amount claimed-amount) u0))
    (unvested-amount (- (get total-amount schedule) vested-amount))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    
    (if (> remaining-claimable u0)
      (try! (as-contract (stx-transfer? remaining-claimable tx-sender beneficiary)))
      true
    )
    
    (if (> unvested-amount u0)
      (try! (as-contract (stx-transfer? unvested-amount tx-sender (var-get owner))))
      true
    )
    
    (map-set vesting-schedules
      { beneficiary: beneficiary }
      (merge schedule { 
        active: false,
        claimed-amount: (get total-amount schedule)
      })
    )
    
    (ok { 
      vested-paid: remaining-claimable,
      unvested-returned: unvested-amount 
    })
  )
)

(define-public (update-vesting-schedule
  (beneficiary principal)
  (new-total-amount uint)
  (new-duration uint)
)
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (vested-amount (unwrap! (calculate-vested-amount beneficiary) ERR_SCHEDULE_NOT_FOUND))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    (asserts! (> new-total-amount u0) ERR_ZERO_AMOUNT)
    (asserts! (> new-duration u0) ERR_INVALID_DURATION)
    (asserts! (>= new-total-amount vested-amount) ERR_INVALID_AMOUNT)
    
    (map-set vesting-schedules
      { beneficiary: beneficiary }
      (merge schedule {
        total-amount: new-total-amount,
        duration: new-duration
      })
    )
    
    (ok true)
  )
)

(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (try! (as-contract (stx-transfer? amount tx-sender (var-get owner))))
    (ok true)
  )
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-schedule-info (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
    (vested-amount (unwrap! (calculate-vested-amount beneficiary) (err u0)))
    (claimable-amount (unwrap! (get-claimable-amount beneficiary) (err u0)))
    (remaining-time (unwrap! (get-remaining-time beneficiary) (err u0)))
  )
    (ok {
      schedule: schedule,
      vested-amount: vested-amount,
      claimable-amount: claimable-amount,
      remaining-time: remaining-time,
      fully-vested: (is-fully-vested beneficiary)
    })
  )
)

(define-read-only (is-schedule-paused (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
  )
    (ok (get paused schedule))
  )
)

(define-read-only (get-pause-time (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) (err u0)))
  )
    (ok (get pause-time schedule))
  )
)

(define-public (batch-create-schedules 
  (schedules (list 10 {
    beneficiary: principal,
    amount: uint,
    start-time: uint,
    cliff-duration: uint,
    duration: uint
  }))
)
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (fold create-single-schedule schedules (ok true))
  )
)

(define-private (create-single-schedule 
  (schedule-data {
    beneficiary: principal,
    amount: uint,
    start-time: uint,
    cliff-duration: uint,
    duration: uint
  })
  (prev-result (response bool uint))
)
  (match prev-result
    ok-value (create-vesting-schedule
      (get beneficiary schedule-data)
      (get amount schedule-data)
      (get start-time schedule-data)
      (get cliff-duration schedule-data)
      (get duration schedule-data)
    )
    err-value (err err-value)
  )
)

(define-read-only (get-multiple-schedules (beneficiaries (list 20 principal)))
  (map get-schedule-info beneficiaries)
)

(define-public (transfer-ownership (new-owner principal) (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get created-by schedule)) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)

    (map-set vesting-schedules
      { beneficiary: beneficiary }
      (merge schedule { created-by: new-owner })
    )

    (ok true)
  )
)

(define-public (pause-vesting-schedule (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    (asserts! (not (get paused schedule)) ERR_SCHEDULE_PAUSED)

    (map-set vesting-schedules
      { beneficiary: beneficiary }
      (merge schedule {
        paused: true,
        pause-time: current-time
      })
    )

    (ok true)
  )
)

(define-public (resume-vesting-schedule (beneficiary principal))
  (let (
    (schedule (unwrap! (get-vesting-schedule beneficiary) ERR_SCHEDULE_NOT_FOUND))
    (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    (pause-time (get pause-time schedule))
    (pause-duration (- current-time pause-time))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (get active schedule) ERR_SCHEDULE_NOT_FOUND)
    (asserts! (get paused schedule) ERR_SCHEDULE_NOT_PAUSED)

    (map-set vesting-schedules
      { beneficiary: beneficiary }
      (merge schedule {
        paused: false,
        start-time: (+ (get start-time schedule) pause-duration),
        cliff-time: (+ (get cliff-time schedule) pause-duration),
        pause-time: u0
      })
    )

    (ok true)
  )
)

(define-public (create-vesting-template
  (name (string-ascii 64))
  (description (string-ascii 256))
  (cliff-duration uint)
  (vesting-duration uint)
)
  (let (
    (template-id (+ (var-get template-counter) u1))
    (existing-template (get-template-by-name name))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (> (len name) u0) ERR_INVALID_TEMPLATE_NAME)
    (asserts! (> vesting-duration u0) ERR_INVALID_DURATION)
    (asserts! (is-none existing-template) ERR_TEMPLATE_ALREADY_EXISTS)
    
    (map-set vesting-templates
      { template-id: template-id }
      {
        name: name,
        description: description,
        cliff-duration: cliff-duration,
        vesting-duration: vesting-duration,
        created-by: tx-sender,
        active: true
      }
    )
    
    (map-set template-name-index
      { name: name }
      { template-id: template-id }
    )
    
    (var-set template-counter template-id)
    (ok template-id)
  )
)

(define-public (update-vesting-template
  (template-id uint)
  (description (string-ascii 256))
  (cliff-duration uint)
  (vesting-duration uint)
)
  (let (
    (template (unwrap! (get-vesting-template template-id) ERR_TEMPLATE_NOT_FOUND))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (get active template) ERR_TEMPLATE_NOT_FOUND)
    (asserts! (> vesting-duration u0) ERR_INVALID_DURATION)
    
    (map-set vesting-templates
      { template-id: template-id }
      (merge template {
        description: description,
        cliff-duration: cliff-duration,
        vesting-duration: vesting-duration
      })
    )
    
    (ok true)
  )
)

(define-public (deactivate-template (template-id uint))
  (let (
    (template (unwrap! (get-vesting-template template-id) ERR_TEMPLATE_NOT_FOUND))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (get active template) ERR_TEMPLATE_NOT_FOUND)
    
    (map-set vesting-templates
      { template-id: template-id }
      (merge template { active: false })
    )
    
    (ok true)
  )
)

(define-public (create-schedule-from-template
  (beneficiary principal)
  (total-amount uint)
  (start-time uint)
  (template-id uint)
)
  (let (
    (template (unwrap! (get-vesting-template template-id) ERR_TEMPLATE_NOT_FOUND))
    (cliff-time (+ start-time (get cliff-duration template)))
    (existing-schedule (get-vesting-schedule beneficiary))
  )
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (get active template) ERR_TEMPLATE_NOT_FOUND)
    (asserts! (> total-amount u0) ERR_ZERO_AMOUNT)
    (asserts! (not (is-eq beneficiary tx-sender)) ERR_INVALID_BENEFICIARY)
    (asserts! (is-none existing-schedule) ERR_SCHEDULE_ALREADY_EXISTS)
    
    (map-set vesting-schedules
      { beneficiary: beneficiary }
      {
        total-amount: total-amount,
        claimed-amount: u0,
        start-time: start-time,
        cliff-time: cliff-time,
        duration: (get vesting-duration template),
        created-by: tx-sender,
        active: true,
        paused: false,
        pause-time: u0
      }
    )
    
    (map-set vesting-balances
      { beneficiary: beneficiary }
      { balance: total-amount }
    )
    
    (ok true)
  )
)

(define-public (create-schedule-from-template-by-name
  (beneficiary principal)
  (total-amount uint)
  (start-time uint)
  (template-name (string-ascii 64))
)
  (let (
    (template-index (unwrap! (get-template-id-by-name template-name) ERR_TEMPLATE_NOT_FOUND))
    (template-id (get template-id template-index))
  )
    (create-schedule-from-template beneficiary total-amount start-time template-id)
  )
)

(define-public (batch-create-from-template
  (template-id uint)
  (schedules (list 10 {
    beneficiary: principal,
    amount: uint,
    start-time: uint
  }))
)
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (fold create-single-from-template-simple schedules (ok template-id))
  )
)

(define-private (create-single-from-template-simple
  (schedule-data {beneficiary: principal, amount: uint, start-time: uint})
  (prev-result (response uint uint))
)
  (match prev-result
    ok-value (match (create-schedule-from-template
      (get beneficiary schedule-data)
      (get amount schedule-data)
      (get start-time schedule-data)
      ok-value
    )
      ok-result (ok ok-value)
      err-result (err err-result)
    )
    err-value (err err-value)
  )
)

(define-private (create-single-from-template
  (schedule-data {
    beneficiary: principal,
    amount: uint,
    start-time: uint,
    template-id: uint
  })
  (prev-result (response bool uint))
)
  (match prev-result
    ok-value (create-schedule-from-template
      (get beneficiary schedule-data)
      (get amount schedule-data)
      (get start-time schedule-data)
      (get template-id schedule-data)
    )
    err-value (err err-value)
  )
)

(define-read-only (get-all-active-templates)
  (filter is-template-active 
    (map get-template-with-id 
      (generate-template-ids (var-get template-counter))
    )
  )
)

(define-private (generate-template-ids (count uint))
  (if (<= count u0)
    (list)
    (unwrap-panic (as-max-len? 
      (map + (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) (list count count count count count count count count count count))
      u10
    ))
  )
)

(define-private (get-template-with-id (template-id uint))
  (match (get-vesting-template template-id)
    some-template some-template
    { name: "", description: "", cliff-duration: u0, vesting-duration: u0, created-by: tx-sender, active: false }
  )
)

(define-private (is-template-active (template {name: (string-ascii 64), description: (string-ascii 256), cliff-duration: uint, vesting-duration: uint, created-by: principal, active: bool}))
  (get active template)
)

(define-public (transfer-beneficiary-rights (new-beneficiary principal))
  (let (
    (current-schedule (unwrap! (get-vesting-schedule tx-sender) ERR_SCHEDULE_NOT_FOUND))
    (current-balance (unwrap! (map-get? vesting-balances { beneficiary: tx-sender }) ERR_SCHEDULE_NOT_FOUND))
    (new-schedule-exists (get-vesting-schedule new-beneficiary))
  )
    (asserts! (get active current-schedule) ERR_SCHEDULE_NOT_FOUND)
    (asserts! (is-none new-schedule-exists) ERR_SCHEDULE_ALREADY_EXISTS)
    (asserts! (not (is-eq tx-sender new-beneficiary)) ERR_INVALID_BENEFICIARY)
    
    (map-delete vesting-schedules { beneficiary: tx-sender })
    (map-set vesting-schedules { beneficiary: new-beneficiary } current-schedule)
    
    (map-delete vesting-balances { beneficiary: tx-sender })
    (map-set vesting-balances { beneficiary: new-beneficiary } current-balance)
    
    (map-delete claim-delegates { beneficiary: tx-sender })
    
    (ok true)
  )
)
