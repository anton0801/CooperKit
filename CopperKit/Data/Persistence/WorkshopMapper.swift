import Foundation

/// Converts between the stored document and the domain. Decoding is lenient field by
/// field; records that lack the identifiers everything else hangs off are skipped
/// rather than invented.
enum WorkshopMapper {
    // MARK: - Decode

    static func workshop(from dto: WorkshopDocumentDTO) -> Workshop {
        let epoch = Date(timeIntervalSince1970: 0)
        var workshop = Workshop()

        workshop.locations = (dto.locations ?? []).compactMap { d in
            guard let id = d.id else { return nil }
            return StorageLocation(id: id, name: d.name ?? "Location", roomZone: d.roomZone ?? "",
                                   shelfLabel: d.shelfLabel ?? "", notes: d.notes ?? "",
                                   createdAt: d.createdAt ?? epoch, updatedAt: d.updatedAt ?? d.createdAt ?? epoch)
        }

        workshop.tools = (dto.tools ?? []).compactMap { d in
            guard let id = d.id, let home = d.homeLocationID else { return nil }
            var cost: PurchaseCost?
            if let text = d.costAmount, let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
               let currency = d.costCurrency {
                cost = PurchaseCost(amount: amount, currencyCode: currency)
            }
            return Tool(id: id, name: d.name ?? "Tool",
                        category: d.category.flatMap(ToolCategory.init(rawValue:)) ?? .other,
                        trackingMode: d.trackingMode.flatMap(TrackingMode.init(rawValue:)) ?? .identicalUnits,
                        homeLocationID: home, ownLabel: d.ownLabel ?? "", serialNumber: d.serialNumber ?? "",
                        photoIDs: d.photoIDs ?? [], notes: d.notes ?? "", purchaseDate: d.purchaseDate,
                        purchaseCost: cost, archivedAt: d.archivedAt,
                        createdAt: d.createdAt ?? epoch, updatedAt: d.updatedAt ?? d.createdAt ?? epoch)
        }

        workshop.kits = (dto.kits ?? []).compactMap { d in
            guard let id = d.id else { return nil }
            let lines: [KitLine] = (d.lines ?? []).compactMap { l in
                guard let toolID = l.toolID else { return nil }
                return KitLine(id: l.id ?? UUID(), toolID: toolID, toolNameSnapshot: l.toolName ?? "Tool",
                               requiredQuantity: max(1, l.requiredQuantity ?? 1))
            }
            return KitTemplate(id: id, name: d.name ?? "Kit", purpose: d.purpose ?? "", lines: lines,
                               preparationNote: d.preparationNote ?? "", archivedAt: d.archivedAt,
                               createdAt: d.createdAt ?? epoch, updatedAt: d.updatedAt ?? d.createdAt ?? epoch)
        }

        workshop.preparations = (dto.preparations ?? []).compactMap { d in
            guard let id = d.id else { return nil }
            let lines: [PreparationLine] = (d.lines ?? []).compactMap { l in
                guard let toolID = l.toolID else { return nil }
                return PreparationLine(id: l.id ?? UUID(), templateToolID: l.templateToolID, toolID: toolID,
                                       toolNameSnapshot: l.toolName ?? "Tool",
                                       requiredQuantity: max(1, l.requiredQuantity ?? 1),
                                       runQuantity: max(1, l.runQuantity ?? l.requiredQuantity ?? 1),
                                       isPrepared: l.isPrepared ?? false, isRemoved: l.isRemoved ?? false)
            }
            return PreparationRun(id: id, kitID: d.kitID, title: d.title ?? "Preparation",
                                  sourceHandoverID: d.sourceHandoverID, lines: lines, runNote: d.runNote ?? "",
                                  createdAt: d.createdAt ?? epoch, updatedAt: d.updatedAt ?? d.createdAt ?? epoch)
        }

        workshop.handovers = (dto.handovers ?? []).compactMap { d in
            guard let id = d.id, let started = d.startedAt else { return nil }
            let lines: [HandoverLine] = (d.lines ?? []).compactMap { l in
                guard let lineID = l.id, let toolID = l.toolID else { return nil }
                return HandoverLine(id: lineID, toolID: toolID, toolNameSnapshot: l.toolName ?? "Tool",
                                    quantity: max(0, l.quantity ?? 0))
            }
            let returns: [ReturnRecord] = (d.returns ?? []).compactMap { r in
                guard let rid = r.id else { return nil }
                let rlines: [ReturnLine] = (r.lines ?? []).compactMap { l in
                    guard let lineID = l.lineID, let toolID = l.toolID else { return nil }
                    return ReturnLine(lineID: lineID, toolID: toolID,
                                      returnedToAvailable: max(0, l.returnedToAvailable ?? 0),
                                      needsService: max(0, l.needsService ?? 0), lost: max(0, l.lost ?? 0),
                                      issueNote: l.issueNote ?? "")
                }
                let at = r.returnedAt ?? r.recordedAt ?? started
                return ReturnRecord(id: rid, operationID: r.operationID ?? rid, returnedAt: at,
                                    recordedAt: r.recordedAt ?? at, note: r.note ?? "", lines: rlines)
            }
            return Handover(id: id, operationID: d.operationID ?? id,
                            mode: d.mode.flatMap(HandoverMode.init(rawValue:)) ?? .loan,
                            purpose: d.purpose ?? "Handover", recipientName: d.recipientName ?? "",
                            contactNote: d.contactNote ?? "", startedAt: started, dueAt: d.dueAt ?? started,
                            dueTimeZoneID: d.dueTimeZoneID ?? TimeZone.current.identifier, lines: lines,
                            conditionOutNote: d.conditionOutNote ?? "", preparationSummary: d.preparationSummary ?? "",
                            kitID: d.kitID, kitNameSnapshot: d.kitName ?? "", returns: returns,
                            createdAt: d.createdAt ?? started, updatedAt: d.updatedAt ?? d.createdAt ?? started)
        }

        workshop.serviceRecords = (dto.serviceRecords ?? []).compactMap { d in
            guard let id = d.id, let toolID = d.toolID else { return nil }
            let source: ServiceSource
            if d.sourceKind == "handoverReturn", let handoverID = d.sourceHandoverID {
                source = .handoverReturn(handoverID: handoverID, holder: d.sourceHolder ?? "")
            } else {
                source = .manual
            }
            let resolutions: [ServiceResolution] = (d.resolutions ?? []).compactMap { r in
                guard let rid = r.id, let kind = r.kind.flatMap(ServiceResolutionKind.init(rawValue:)) else { return nil }
                return ServiceResolution(id: rid, kind: kind, quantity: max(0, r.quantity ?? 0), note: r.note ?? "",
                                         at: r.at ?? d.openedAt ?? epoch)
            }
            let opened = d.openedAt ?? epoch
            return ServiceRecord(id: id, toolID: toolID, toolNameSnapshot: d.toolName ?? "Tool",
                                 quantity: max(0, d.quantity ?? 0), issue: d.issue ?? "", notes: d.notes ?? "",
                                 openedAt: opened, source: source, resolutions: resolutions,
                                 updatedAt: d.updatedAt ?? opened)
        }

        workshop.movements = (dto.movements ?? []).compactMap { d in
            guard let id = d.id, let toolID = d.toolID,
                  let kind = d.kind.flatMap(StockMovementKind.init(rawValue:)) else { return nil }
            return StockMovement(id: id, toolID: toolID, kind: kind, quantity: max(0, d.quantity ?? 0),
                                 reason: d.reason ?? "", at: d.at ?? epoch, handoverID: d.handoverID,
                                 serviceRecordID: d.serviceRecordID, inventoryCheckID: d.inventoryCheckID)
        }

        workshop.inventoryChecks = (dto.inventoryChecks ?? []).compactMap { d in
            guard let id = d.id else { return nil }
            let lines: [InventoryCheckLine] = (d.lines ?? []).compactMap { l in
                guard let toolID = l.toolID else { return nil }
                return InventoryCheckLine(toolID: toolID, toolNameSnapshot: l.toolName ?? "Tool",
                                          expectedAtHome: l.expectedAtHome ?? 0, counted: l.counted ?? 0)
            }
            return InventoryCheck(id: id, locationID: d.locationID, locationNameSnapshot: d.locationName ?? "",
                                  performedAt: d.performedAt ?? epoch, note: d.note ?? "", lines: lines)
        }

        workshop.activity = (dto.activity ?? []).compactMap { d in
            guard let id = d.id, let kind = d.kind.flatMap(ActivityKind.init(rawValue:)) else { return nil }
            return ActivityEvent(id: id, at: d.at ?? epoch, kind: kind, title: d.title ?? "", detail: d.detail ?? "",
                                 toolIDs: d.toolIDs ?? [], handoverID: d.handoverID, serviceRecordID: d.serviceRecordID,
                                 locationID: d.locationID, kitID: d.kitID)
        }

        let standard = AppSettings.standard()
        workshop.settings = AppSettings(
            defaultLoanDays: dto.settings?.defaultLoanDays.map { min(max($0, Limits.loanDays.lowerBound), Limits.loanDays.upperBound) } ?? standard.defaultLoanDays,
            defaultCurrencyCode: dto.settings?.defaultCurrencyCode ?? standard.defaultCurrencyCode,
            dueRemindersEnabled: dto.settings?.dueRemindersEnabled ?? standard.dueRemindersEnabled
        )
        return workshop
    }

    // MARK: - Encode

    static func dto(from w: Workshop, savedAt: Date) -> WorkshopDocumentDTO {
        let posix = Locale(identifier: "en_US_POSIX")
        return WorkshopDocumentDTO(
            schemaVersion: Workshop.currentSchemaVersion,
            savedAt: savedAt,
            tools: w.tools.map {
                ToolDTO(id: $0.id, name: $0.name, category: $0.category.rawValue, trackingMode: $0.trackingMode.rawValue,
                        homeLocationID: $0.homeLocationID, ownLabel: $0.ownLabel, serialNumber: $0.serialNumber,
                        photoIDs: $0.photoIDs, notes: $0.notes, purchaseDate: $0.purchaseDate,
                        costAmount: $0.purchaseCost.map { NSDecimalNumber(decimal: $0.amount).description(withLocale: posix) },
                        costCurrency: $0.purchaseCost?.currencyCode, archivedAt: $0.archivedAt,
                        createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            locations: w.locations.map {
                LocationDTO(id: $0.id, name: $0.name, roomZone: $0.roomZone, shelfLabel: $0.shelfLabel, notes: $0.notes,
                            createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            kits: w.kits.map {
                KitDTO(id: $0.id, name: $0.name, purpose: $0.purpose,
                       lines: $0.lines.map { KitLineDTO(id: $0.id, toolID: $0.toolID, toolName: $0.toolNameSnapshot, requiredQuantity: $0.requiredQuantity) },
                       preparationNote: $0.preparationNote, archivedAt: $0.archivedAt,
                       createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            preparations: w.preparations.map {
                PreparationDTO(id: $0.id, kitID: $0.kitID, title: $0.title, sourceHandoverID: $0.sourceHandoverID,
                               lines: $0.lines.map {
                                   PreparationLineDTO(id: $0.id, templateToolID: $0.templateToolID, toolID: $0.toolID,
                                                      toolName: $0.toolNameSnapshot, requiredQuantity: $0.requiredQuantity,
                                                      runQuantity: $0.runQuantity, isPrepared: $0.isPrepared, isRemoved: $0.isRemoved)
                               },
                               runNote: $0.runNote, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            handovers: w.handovers.map { h in
                HandoverDTO(id: h.id, operationID: h.operationID, mode: h.mode.rawValue, purpose: h.purpose,
                            recipientName: h.recipientName, contactNote: h.contactNote, startedAt: h.startedAt,
                            dueAt: h.dueAt, dueTimeZoneID: h.dueTimeZoneID,
                            lines: h.lines.map { HandoverLineDTO(id: $0.id, toolID: $0.toolID, toolName: $0.toolNameSnapshot, quantity: $0.quantity) },
                            conditionOutNote: h.conditionOutNote, preparationSummary: h.preparationSummary,
                            kitID: h.kitID, kitName: h.kitNameSnapshot,
                            returns: h.returns.map { r in
                                ReturnRecordDTO(id: r.id, operationID: r.operationID, returnedAt: r.returnedAt,
                                                recordedAt: r.recordedAt, note: r.note,
                                                lines: r.lines.map {
                                                    ReturnLineDTO(lineID: $0.lineID, toolID: $0.toolID,
                                                                  returnedToAvailable: $0.returnedToAvailable,
                                                                  needsService: $0.needsService, lost: $0.lost,
                                                                  issueNote: $0.issueNote)
                                                })
                            },
                            createdAt: h.createdAt, updatedAt: h.updatedAt)
            },
            serviceRecords: w.serviceRecords.map { s in
                var kind = "manual", handoverID: UUID?, holder: String?
                if case let .handoverReturn(id, name) = s.source { kind = "handoverReturn"; handoverID = id; holder = name }
                return ServiceDTO(id: s.id, toolID: s.toolID, toolName: s.toolNameSnapshot, quantity: s.quantity,
                                  issue: s.issue, notes: s.notes, openedAt: s.openedAt, sourceKind: kind,
                                  sourceHandoverID: handoverID, sourceHolder: holder,
                                  resolutions: s.resolutions.map {
                                      ServiceResolutionDTO(id: $0.id, kind: $0.kind.rawValue, quantity: $0.quantity, note: $0.note, at: $0.at)
                                  },
                                  updatedAt: s.updatedAt)
            },
            movements: w.movements.map {
                MovementDTO(id: $0.id, toolID: $0.toolID, kind: $0.kind.rawValue, quantity: $0.quantity, reason: $0.reason,
                            at: $0.at, handoverID: $0.handoverID, serviceRecordID: $0.serviceRecordID,
                            inventoryCheckID: $0.inventoryCheckID)
            },
            inventoryChecks: w.inventoryChecks.map {
                InventoryCheckDTO(id: $0.id, locationID: $0.locationID, locationName: $0.locationNameSnapshot,
                                  performedAt: $0.performedAt, note: $0.note,
                                  lines: $0.lines.map { InventoryLineDTO(toolID: $0.toolID, toolName: $0.toolNameSnapshot, expectedAtHome: $0.expectedAtHome, counted: $0.counted) })
            },
            activity: w.activity.map {
                ActivityDTO(id: $0.id, at: $0.at, kind: $0.kind.rawValue, title: $0.title, detail: $0.detail,
                            toolIDs: $0.toolIDs, handoverID: $0.handoverID, serviceRecordID: $0.serviceRecordID,
                            locationID: $0.locationID, kitID: $0.kitID)
            },
            settings: SettingsDTO(defaultLoanDays: w.settings.defaultLoanDays,
                                  defaultCurrencyCode: w.settings.defaultCurrencyCode,
                                  dueRemindersEnabled: w.settings.dueRemindersEnabled)
        )
    }
}
