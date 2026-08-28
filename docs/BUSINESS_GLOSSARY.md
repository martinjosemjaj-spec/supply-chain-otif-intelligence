# OTIF_Guardian - Business Glossary

**Version:** 1.0  
**Domain:** Supply Chain — OTIF Performance Management

---

## Core Business Terms

---

### Fulfillment & Delivery

| Term | Definition | Context |
|------|-----------|---------|
| **OTIF** | On-Time In-Full. A delivery meets OTIF when it arrives on or before the requested date AND contains the full ordered quantity. | Primary KPI for supply chain performance. |
| **On-Time** | A delivery or shipment that arrives on or before the committed/requested delivery date. | Measured at PO line level (inbound) or customer order level (outbound). |
| **In-Full** | A delivery where the received quantity equals or exceeds the ordered quantity with no short-close. | Partial deliveries fail the In-Full criterion. |
| **Fill Rate** | The percentage of demand satisfied from available stock without backorder. | Measured at material-plant level. |
| **Perfect Order** | An order delivered on-time, in-full, with correct documentation, and no damage. | Superset of OTIF; includes quality and admin dimensions. |
| **Service Level** | The probability of not stocking out during a replenishment cycle. | Expressed as percentage; target varies by ABC class. |

---

### Procurement

| Term | Definition | Context |
|------|-----------|---------|
| **Purchase Order (PO)** | A legally binding document committing the buyer to procure specified materials from a supplier at agreed terms. | Header + lines structure. |
| **Blanket Order** | A long-term PO with agreed pricing and total quantity, released in scheduled deliveries. | Used for high-volume, recurring materials. |
| **Expedite Order** | A PO issued with shortened lead time, typically at premium cost, to address urgent supply gaps. | Indicator of planning failure or demand spike. |
| **Lead Time** | Calendar days from PO issuance to goods receipt at the receiving plant. | Includes supplier processing, production, and transit. |
| **Promised Date** | The delivery date confirmed by the supplier in response to the PO. | May differ from requested date. |
| **Requested Date** | The delivery date specified by the buyer on the PO. | Represents the business need date. |
| **Short Close** | Closure of a PO line before full quantity is received, accepting the shortfall. | Counted as In-Full failure. |
| **MOQ** | Minimum Order Quantity. The smallest quantity a supplier will accept on a single order. | Constraint on replenishment planning. |

---

### Inventory & Supply

| Term | Definition | Context |
|------|-----------|---------|
| **Safety Stock** | Buffer inventory held to protect against variability in demand or supply lead time. | Expressed in days of supply or units. |
| **Reorder Point** | The inventory level at which a replenishment order should be triggered. | ROP = (Daily Demand * Lead Time) + Safety Stock. |
| **Days of Supply** | The number of days current on-hand inventory can satisfy average daily demand. | Key measure of inventory health. |
| **Available Stock** | On-hand quantity minus reserved (allocated) quantity. | What can be committed to new demand. |
| **Projected Stock** | Available stock plus in-transit quantities. | Forward-looking availability. |
| **Stockout** | A condition where available stock is zero and demand cannot be fulfilled. | Triggers expedite orders or customer delays. |
| **ABC Classification** | Pareto segmentation of materials by annual consumption value. A=top 80% value, B=next 15%, C=remaining 5%. | Drives differentiated inventory policies. |

---

### Logistics

| Term | Definition | Context |
|------|-----------|---------|
| **Transport Mode** | The method of goods movement: AIR, OCEAN, TRUCK, RAIL, MULTIMODAL. | Determines cost, speed, and carbon impact. |
| **Transit Time** | Calendar days from shipment departure to arrival at destination. | Varies by mode and lane. |
| **Carrier** | A logistics provider responsible for physical transport of goods. | Contracted per lane or spot-market. |
| **Transport Lane** | A defined route between an origin country and destination country with standard mode, time, and cost. | Network topology element. |
| **Bill of Lading (BOL)** | Document acknowledging receipt of goods for shipment. | Legal proof of shipment. |
| **ETA** | Estimated Time of Arrival. Predicted date of shipment arrival at destination. | Updated during transit. |

---

### Quality

| Term | Definition | Context |
|------|-----------|---------|
| **Inspection Result** | Outcome of goods receipt quality check: ACCEPTED, CONDITIONAL, REJECTED. | Gate between receipt and available inventory. |
| **NCR** | Non-Conformance Report. Formal record of a quality failure against a supplier. | Triggers corrective action and may affect supplier score. |
| **Quality Score** | Composite supplier quality rating (0-100) based on historical inspection results, NCRs, and response time. | Used in supplier tiering decisions. |

---

### Supplier Management

| Term | Definition | Context |
|------|-----------|---------|
| **Supplier Tier** | Strategic classification: Tier-1 (strategic partner), Tier-2 (preferred), Tier-3 (approved). | Determines allocation priority and relationship investment. |
| **Dual Sourcing** | Strategy of maintaining at least two qualified suppliers for a material to mitigate risk. | Required for A-class critical materials. |
| **Preference Rank** | Ordered priority among alternate suppliers for a material (1=primary, 2+=alternate). | Drives sourcing allocation. |
| **Probation** | Supplier status indicating performance below threshold; subject to corrective action plan. | May restrict new PO allocation. |

---

### Demand & Planning

| Term | Definition | Context |
|------|-----------|---------|
| **Firm Demand** | Committed requirement backed by a customer order or production schedule. | Highest certainty; drives procurement. |
| **Planned Demand** | Scheduled requirement from MRP/MPS not yet released as firm. | Medium certainty. |
| **Forecast Demand** | Statistical projection of future requirements. | Lowest certainty; used for capacity and budget planning. |
| **MRP** | Material Requirements Planning. System logic that nets demand against supply to generate planned orders. | Core planning engine. |
| **Demand Sensing** | Near-term demand signal adjustment using real-time data. | Reduces forecast error within planning horizon. |

---

### Customer Fulfillment

| Term | Definition | Context |
|------|-----------|---------|
| **Customer Order** | A confirmed request from a customer for goods to be shipped from a plant. | Revenue-generating commitment. |
| **Order Value** | Total monetary amount of a customer order. | Used for revenue impact analysis of OTIF failures. |
| **Partial Shipment** | A customer order shipped with less than full quantity. | Fails the In-Full criterion. |
| **Backorder** | Unfulfilled portion of a customer order due to insufficient stock. | Requires expediting or rescheduling. |

---

## Abbreviations

| Abbrev | Expansion |
|--------|-----------|
| OTIF | On-Time In-Full |
| PO | Purchase Order |
| MOQ | Minimum Order Quantity |
| ROP | Reorder Point |
| MRP | Material Requirements Planning |
| MPS | Master Production Schedule |
| NCR | Non-Conformance Report |
| BOL | Bill of Lading |
| ETA | Estimated Time of Arrival |
| UOM | Unit of Measure |
| BK | Business Key |
| FK | Foreign Key |
| PK | Primary Key |
| DOS | Days of Supply |
| OTD | On-Time Delivery |
