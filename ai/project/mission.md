# Project Mission

This repository provides a **cloud-migration learning sandbox** for monthly caseload forecasting. It uses publicly available Alberta Income Support data to create a complete, self-contained forecasting workflow that analysts can run on-premises, then migrate to Azure ML infrastructure with guidance from cloud platform partners.

The repo prioritizes **simplicity over realism**: model complexity is deliberately constrained to three tiers (naive baseline, ARIMA, augmented ARIMA) to focus learning on cloud orchestration, not statistical nuance. Once the Azure pipeline is stable, it will be re-grafted onto real, operationally complex production data.

## Objectives

- **Establish end-to-end on-prem pipeline**: Ferry → Ellis → Mint → Train → Forecast → Report (EDA informs Mint but is not a sequential gate; monthly refresh cadence)
- **Demonstrate Azure ML migration path**: Understand compute instances, model registry, MLflow, endpoint serving, and orchestration for government analytics use cases
- **Enable analyst fluency**: Analysts with solid R/stats backgrounds gain hands-on experience with Azure ML concepts and terminology
- **Inform cloud adoption strategy**: Clarify where cloud compute is indispensable (e.g., large-scale estimation) vs. where on-prem suffices
- **Prototype report serving & security**: Explore delivery mechanisms (static HTML → SharePoint, Azure Static Web Apps, Power BI) with AAD-based access control

## Success Metrics

- **Pipeline completeness**: Ferry, Ellis, Mint, Train, Forecast, Report scripts all execute without manual intervention
- **Reproducibility**: Re-running the pipeline with same data produces identical forecasts (deterministic seeds, versioned dependencies)
- **Azure readiness**: Project structure and code patterns align with Azure ML pipeline requirements (even if not yet deployed)
- **Report delivery**: Static HTML renders successfully, displays 24-month horizon forecasts with model performance diagnostics

## Non-Goals

- **Model sophistication**: This is not a production forecasting system. Model accuracy is secondary to workflow clarity.
- **Real-time inference**: Monthly batch forecasting only; no streaming data or live endpoints (yet).
- **Automated deployment**: Azure migration is Phase 2. Phase 1 establishes local workflow and confirms Azure requirements.
- **Multi-program disaggregation**: Initial scope is total caseload only. Program-level forecasts deferred to re-graft phase.

## Stakeholders

- **Lead Analyst**: Primary user; builds pipeline, learns Azure ML, documents learnings
- **Analytics Team**: Secondary audience for static HTML reports; validates workflow patterns for reusability
- **Infrastructure Lead**: Infrastructure and product ownership guidance for Azure ML setup
- **Data Strategy Lead**: Strategic advisor on cloud adoption patterns and organizational needs
- **Cloud Platform Partners**: Azure ML specialists providing migration guidance

