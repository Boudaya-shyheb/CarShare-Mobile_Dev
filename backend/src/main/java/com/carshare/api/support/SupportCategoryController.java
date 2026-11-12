package com.carshare.api.support;

import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/support/categories")
public class SupportCategoryController {
    private final SupportService support;

    public SupportCategoryController(SupportService support) { this.support = support; }

    @GetMapping
    public List<SupportService.CategoryView> categories() {
        return support.activeCategories();
    }
}
