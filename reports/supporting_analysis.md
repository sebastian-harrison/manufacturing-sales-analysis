# Supporting Sales Analysis

These tables extend the [commercial report](../README.md) with annual
comparisons, the full default account review and the comparable-item breakdown.
Monetary tables use millions of dollars at the fixed 2014 exchange rate.
Linked CSV results retain the original source amounts.

## Annual sales comparisons

| Comparison | Prior sales, $m | Current sales, $m | Change, $m | Change % |
| --- | ---: | ---: | ---: | ---: |
| 2012 vs 2011 | 80.66 | 66.73 | -13.92 | -17.3% |
| 2013 vs 2012 | 66.73 | 60.30 | -6.44 | -9.6% |
| 2014 vs 2013 | 60.30 | 47.54 | -12.75 | -21.2% |

[Annual results](annual_comparisons.csv) · [Monthly history](company_month.csv).

## Account losses

| Account (code) | Prior sales, $m | Current sales, $m | Change, $m | Change % | Company share |
| --- | ---: | ---: | ---: | ---: | ---: |
| Queensway Aluminium (CIQ0001) | 16.23 | 12.17 | -4.05 | -25.0% | 25.6% |
| P.G.N (CIP0001) | 10.16 | 8.03 | -2.13 | -21.0% | 16.9% |
| Asaba Aluminium (CIA0013) | 8.80 | 6.75 | -2.04 | -23.2% | 14.2% |
| Borno Aluminium (CIB0004) | 2.69 | 1.11 | -1.58 | -58.7% | 2.3% |
| Tower Building Products (CIT0005) | 10.52 | 9.34 | -1.17 | -11.2% | 19.7% |
| Tower Galvanized Products (CIT0008) | 2.93 | 2.39 | -0.54 | -18.5% | 5.0% |
| Akure plant (CIA0004) | 1.01 | 0.57 | -0.45 | -44.3% | 1.2% |
| Illorin plant (CIT0003) | 0.85 | 0.63 | -0.22 | -26.0% | 1.3% |

The four leading losses total **$9.81 million**, or **76.9%** of the company's
net decline. The full eight-account review represents **95.6%**. Across all
accounts, gross losses of **$14.80 million** were partly offset by **$2.05 million**
of gains. 

[Default account results](account_review_priorities.csv) ·
[All account comparisons](../data/exports/account_year_summary.csv).

## Specification contributions

| Thickness label | Prior sales, $m | Current sales, $m | Change, $m | Share of company net decline |
| --- | ---: | ---: | ---: | ---: |
| 0.55 | 17.89 | 13.27 | -4.62 | 36.2% |
| 0.45 | 17.04 | 12.76 | -4.28 | 33.5% |
| 0.42 | 9.46 | 5.40 | -4.06 | 31.8% |

These three labels lost a combined **$12.96 million**, exceeding the net company
decline because other thicknesses gained sales. Within `0.42`, P.G.N's loss was
**$2.73 million**, or **67.2%** of that specification's net loss. Its gains in
`0.4`, `0.40B` and `0.55` softened its overall account decline.

[Complete contributions](revenue_driver_details.csv) ·
[Account/specification comparisons](customer_thickness_changes.csv).

## Customer concentration

| Year | Company sales, $m | Top-five sales, $m | Top-one share | Top-five share |
| --- | ---: | ---: | ---: | ---: |
| 2011 | 80.66 | 61.06 | 19.9% | 75.7% |
| 2012 | 66.73 | 51.88 | 21.4% | 77.7% |
| 2013 | 60.30 | 48.64 | 26.9% | 80.7% |
| 2014 | 47.54 | 38.69 | 25.6% | 81.4% |

The annual top five are re-ranked, so their membership can change. Following the
same five largest customers of 2011 provides a second view: their sales fell
**38.7%** to **$37.41 million** by 2014, while sales outside that group fell
**48.1%**. The fixed group's share rose from **75.7% to 78.7%**. 

[Annual concentration](concentration_year.csv) ·
[Fixed 2011 customer group](concentration_fixed_cohort.csv).

## Comparable-item sales change

The item breakdown separates the change associated with reported quantity and
realized price, plus sales from items recorded in only one comparison year. Realized
price is sales divided by reported quantity and can reflect discounts and
customer mix.

| Component, $ millions | 2012 vs 2011 | 2013 vs 2012 | 2014 vs 2013 |
| --- | ---: | ---: | ---: |
| Matched-item quantity association | -20.56 | -0.88 | -13.51 |
| Matched-item realized-price association | 0.94 | -4.03 | 0.69 |
| Current-only item sales | 8.41 | 2.68 | 2.66 |
| Prior-only item sales | -2.71 | -4.21 | -2.60 |
| Unresolved change | 0.00 | 0.00 | 0.00 |
| **Company sales change** | **-13.92** | **-6.44** | **-12.75** |

| Comparison | Matched items | Prior sales coverage | Current sales coverage |
| --- | ---: | ---: | ---: |
| 2012 vs 2011 | 210 | 96.64% | 87.39% |
| 2013 vs 2012 | 200 | 93.70% | 95.55% |
| 2014 vs 2013 | 195 | 95.69% | 94.41% |

The focused 2014 sensitivity checks give:

| 2014 comparison | Quantity association, $m | Realized-price association, $m | Unresolved change, $m | Prior coverage | Current coverage |
| --- | ---: | ---: | ---: | ---: | ---: |
| Base item matching | -13.51 | 0.69 | 0.00 | 95.7% | 94.4% |
| Description variants unresolved | -13.01 | 0.69 | -0.50 | 90.0% | 88.2% |
| Exclude zero-sales lines | -13.44 | 0.62 | 0.00 | 95.7% | 94.4% |
| Match item/customer pairs | -11.21 | 0.56 | 0.00 | 89.1% | 90.6% |

[Component inputs](../data/exports/price_quantity_bridge.csv) ·
[Sensitivity results](bridge_sensitivity.csv).
