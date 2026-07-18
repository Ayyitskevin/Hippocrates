import Foundation

/// P-003: a clean install offers this ASHP-derived starter set on one explicit
/// first-run screen. The user reviews the actual labels and accepts, edits, or
/// skips them; nothing is ever seeded silently. Shipping the list as source
/// keeps the privacy manifest the sole app resource.
enum StarterTaxonomy {
    static let interventionTypeLabels: [String] = [
        "Renal dose adjustment",
        "Hepatic dose adjustment",
        "Dose optimization",
        "IV to PO conversion",
        "Therapeutic duplication",
        "Drug interaction management",
        "Allergy clarification",
        "Antimicrobial de-escalation",
        "Therapeutic drug monitoring",
        "Pharmacokinetic consult",
        "Medication reconciliation",
        "Formulary interchange",
        "Discontinue unnecessary therapy",
        "Initiate indicated therapy",
        "Adverse drug event management",
        "Patient education"
    ]

    static let drugClassLabels: [String] = [
        "Antimicrobials",
        "Anticoagulants",
        "Analgesics and opioids",
        "Cardiovascular agents",
        "Anticonvulsants",
        "Diabetes agents",
        "Immunosuppressants",
        "Psychotropics",
        "Chemotherapy",
        "Fluids and electrolytes",
        "Gastrointestinal agents",
        "Respiratory agents"
    ]

    static let serviceLineLabels: [String] = [
        "Critical care",
        "Emergency department",
        "Internal medicine",
        "Surgery",
        "Cardiology",
        "Oncology",
        "Pediatrics",
        "Obstetrics",
        "Behavioral health",
        "Ambulatory care"
    ]
}
